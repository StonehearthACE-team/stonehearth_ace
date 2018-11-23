local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('connection_utils')
local connection_utils = {}

local MIDDLE_OFFSET = Point3(0.5, 0, 0.5)

function connection_utils.import_region(region)
   local r = Region3()
   for _, cube in pairs(region) do
      local c = radiant.util.to_cube3(cube)
      if c then
         r:add_cube(c)
      end
   end
   if r:get_area() > 0 then
      return r
   else
      return nil
   end
end

function connection_utils.rotate_region(region, origin, rotation)
   return region:translated(origin - MIDDLE_OFFSET):rotated(rotation):translated(MIDDLE_OFFSET - origin)
end

function connection_utils.combine_tables(into, from)
   for k, v in pairs(from) do
      into[k] = v
   end
   return into
end

function connection_utils.combine_type_tables(t1, t2)
   -- this is called with the player-specific and all-players graphs_changed tables
   -- since a connection type is one or the other, we can simply combine all the types found
   -- this may cause issues if people change that property on a connection type in the middle of a game, but they really shouldn't do that
   local t = {}

   for _, copy_from in ipairs({t1, t2}) do
      for type, conns in pairs(copy_from) do
         if not t[type] then
            t[type] = {}
         end
         connection_utils.combine_tables(t[type], conns)
      end
   end

   return t
end

function connection_utils.combine_entity_tables(t1, t2)
   -- this is called with the player-specific and all-players connected_entities tables
   local t = {}
   
   for _, copy_from in ipairs({t1, t2}) do
      for entity, data in pairs(copy_from) do
         if not t[entity] then
            t[entity] = {}
         end
         for type, type_data in pairs(data) do
            if not t[entity][type] then
               t[entity][type] = {}
            end
            t[entity][type].available = type_data.available
            if not t[entity][type].available_connectors then
               t[entity][type].available_connectors = {}
            end
            t[entity][type].connected = type_data.connected
            if not t[entity][type].connected_connectors then
               t[entity][type].connected_connectors = {}
            end
            connection_utils.combine_tables(t[entity][type].available_connectors, type_data.available_connectors or {})
            connection_utils.combine_tables(t[entity][type].connected_connectors, type_data.connected_connectors or {})
         end
      end
   end

   return t
end

-- called from item_placer (on the client), passing the cursor entity
-- check to see if the cursor entity in its current position has a connector that matches up with
-- an available connector on this entity in its current position
function connection_utils._item_placer_can_place(item_uri, cursor, target)
   local cursor_conns = radiant.entities.get_component_data(item_uri, 'stonehearth_ace:connection')
   local target_conns = radiant.entities.get_component_data(target.entity, 'stonehearth_ace:connection')
   local target_stats = stonehearth_ace.connection_client:get_entity_connection_stats(target.entity:get_id())

   if cursor_conns and target_conns then
      for type, stats in pairs(target_stats) do
         if stats.available then
            local cursor_conn = cursor_conns[type] or {}
            for name, conn in pairs(cursor_conn.connectors or {}) do
               -- make sure there's actually a connector specified for this type
               return true
            end

            -- TODO: try to check actual connectors to see if there's a properly positioned available connector
            --[[
            local target_conn = target_conns[type] or {}
            
            for name, connector in pairs(target_conn.connectors) do
               if stats.available_connectors[name] then
                  -- if this connector isn't already connected, check to see if it can connect to a connector in the cursor entity
                  local r1 = rotate_region(radiant.util.to_cube3(connector.region), entity_struct.origin, new_rotation):translated(new_location)
               end
            end
            ]]
         end
      end
   end

   return false
end

-- this is called by the connection service when this entity has any of its connectors change status
function connection_utils._update_entity_connection_data(data, stats)
   for type, type_stats in pairs(stats) do
      local these_stats = data[type]
      if not these_stats then
         these_stats = {available_connectors = {}, connected_connectors = {}}
         data[type] = these_stats
      end
      if type_stats.available ~= nil then
         these_stats.available = type_stats.available
      end
      if type_stats.connected ~= nil then
         these_stats.connected = type_stats.connected
      end
      
      if type_stats.available_connectors then
         for id, available in pairs(type_stats.available_connectors) do
            these_stats.available_connectors[id] = available or nil
         end
      end
      if type_stats.connected_connectors then
         for id, connected in pairs(type_stats.connected_connectors) do
            these_stats.connected_connectors[id] = connected or nil
         end
      end
   end
end

return connection_utils