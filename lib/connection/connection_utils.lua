local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('connection_utils')
local connection_utils = {}

local MIDDLE_OFFSET = Point3(0.5, 0, 0.5)

-- ONLY WORKS FOR CARDINAL ROTATIONS
function connection_utils.rotate_region(region, origin, rotation, align_x, align_z)
   -- if we're aligning to the x axis, rotating to 90 or 270 means we ignore the z offset, and always ignore the x offset
   -- if we're aligning to the z axis, rotating to 0 or 180 means we ignore the x offset, and always ignore the z offset
   local proper_rotation = math.floor((rotation / 90) + 0.5) * 90
   local swap_axes = (proper_rotation + 90) % 180 == 0
   local offset = origin - Point3(align_x and 0 or MIDDLE_OFFSET.x, MIDDLE_OFFSET.y, align_z and 0 or MIDDLE_OFFSET.z)
   --local post_offset = -(offset:rotated(proper_rotation))
   local post_offset = -Point3(swap_axes and offset.z or offset.x, MIDDLE_OFFSET.y, swap_axes and offset.x or offset.z)
   local result = region:translated(offset):rotated(proper_rotation):translated(post_offset)
   --log:debug('rotating region %s %s° (%s°) about %s: %s', region:get_bounds(), rotation, proper_rotation, offset, result:get_bounds())
   return result
end

-- presumably, this should work as a more general version instead of just the four cardinal rotations
-- determine the offset vector, translate the region by that offset, rotate both the region and the vector, then translate the region by the negative of the rotated vector
function connection_utils._rotate_region(region, origin, rotation, align_x, align_z)
   -- if we're aligning to the x axis, rotating to 90 or 270 means we ignore the z offset, and always ignore the x offset
   -- if we're aligning to the z axis, rotating to 0 or 180 means we ignore the x offset, and always ignore the z offset
   local proper_rotation = math.floor(rotation + 0.5)
   local swap_axes = (proper_rotation + 90) % 180 == 0
   local offset = origin - Point3(align_x and 0 or MIDDLE_OFFSET.x, MIDDLE_OFFSET.y, align_z and 0 or MIDDLE_OFFSET.z)
   local post_offset = -(offset:rotated(proper_rotation))
   --local post_offset = Point3(swap_axes and offset.z or offset.x, MIDDLE_OFFSET.y, swap_axes and offset.x or offset.z)
   local result = region:translated(offset):rotated(proper_rotation):translated(post_offset)
   log:debug('rotating region %s %s° (%s°) about %s: %s', region:get_bounds(), rotation, proper_rotation, offset, result:get_bounds())
   return result
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

-- called from item_placer (on the client), passing the cursor entity
-- check to see if the cursor entity in its current position has a connector that matches up with
-- an available connector on this entity in its current position
function connection_utils._item_placer_can_place(item_uri, cursor, target)
   local cursor_conns = radiant.entities.get_component_data(item_uri, 'stonehearth_ace:connection')
   local target_conns = radiant.entities.get_component_data(target.entity, 'stonehearth_ace:connection')
   local target_stats = stonehearth_ace.connection_client:get_entity_connection_stats(target.entity:get_id())

   if cursor_conns and target_conns then
      for type, stats in pairs(target_stats) do
         if stats.num_connections < stats.max_connections then
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
         these_stats = {connectors = {}}
         data[type] = these_stats
      end
      these_stats.num_connections = type_stats.num_connections
      these_stats.max_connections = type_stats.max_connections
      
      if type_stats.connectors then
         for id, connector in pairs(type_stats.connectors) do
            local these_conns = these_stats.connectors[id]
            if not these_conns then
               these_conns = {connected_to = {}}
               these_stats.connectors[id] = these_conns
            end
            these_conns.num_connections = connector.num_connections
            these_conns.max_connections = connector.max_connections

            if connector.connected_to then
               for to_id, info in pairs(connector.connected_to) do
                  these_conns.connected_to[to_id] = info
               end
            end
         end
      end
   end
end

function connection_utils._update_connection_data(data, new_data)
   for entity_id, entity_data in pairs(new_data) do
      local this_entity_data = data[entity_id]
      if not this_entity_data then
         this_entity_data = {}
         data[entity_id] = this_entity_data
      end
      connection_utils._update_entity_connection_data(this_entity_data, entity_data)
   end
end

return connection_utils