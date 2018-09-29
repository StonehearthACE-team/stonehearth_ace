--[[
contains collections of all "connected" entities for a player
these are grouped by connection type; entities can have multiple connection types
]]

local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local region_utils = require 'stonehearth.lib.building.region_utils'

local PlayerConnections = class()

function PlayerConnections:__init()
   
end

function PlayerConnections:initialize()
   self._sv.clump_region_size = 8
   self._sv.entities = {} -- list of all the entities being tracked: [entity id]{id, entity, location, connections}
   -- connections: [type]{max_conections, connectors}
   -- connectors: [name]{max_connections, region, clump_region_keys}
   self._sv.connection_tables = {} -- list of connections by type: [type]{type, entity_structs, connector_locations, graphs}
   -- connector_locations: {clump_region_key: {entity1_id: entity1_struct, entity2_id: entity2_struct}}
end

function PlayerConnections:create(player_id)
   self._sv.player_id = player_id
   self.__saved_variables:mark_changed()
end

function PlayerConnections:register_entity(entity, connections)
   local id = entity:get_id()
   if not self._sv.entities[id] then
      local entity_struct = {id = id, entity = entity, connections = connections}
      self._sv.entities[id] = entity_struct
      entity_struct._parent_trace = entity:add_component('mob'):trace_parent('connection entity added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
         :on_changed(function(parent_entity)
               if not parent_entity then
                  --we were just removed from the world
                  self:_remove_entity_from_graphs(entity_struct)
                  self:_update_connector_locations(entity_struct, false, false)
               else
                  --we were just added to the world
                  self:_update_connector_locations(entity_struct)
                  self:_add_entity_to_graphs(entity_struct)
               end
            end)

            entity_struct._location_trace = entity:add_component('mob'):trace_transform('connection entity moved', _radiant.dm.TraceCategories.SYNC_TRACE)
         :on_changed(function()
               self:_remove_entity_from_graphs(entity_struct)
               self:_update_connector_locations(entity_struct)
               self:_add_entity_to_graphs(entity_struct)
            end)

      -- organize connections by type
      for type, connectors in pairs(connections) do
         -- transform all the region JSON data into Cube3 structures
         for key, connector in pairs(connectors) do
            connector.region = radiant.util.to_cube3(connector.region)
         end
         -- TODO: fix/finish this part (see unregister)
         local conn_tbl = self:get_connections(type)
         if not conn_tbl.entity_structs[id] then
            local e = {entity_struct = entity_struct, connectors = {}}
            conn_tbl.entity_structs[id] = entity_struct

            
         end
      end
   end
end

function PlayerConnections:unregister_entity(entity)
   local id = entity:get_id()
   local entity_struct = self._sv.entities[id]

   -- destroy traces
   if entity_struct._parent_trace then
      entity_struct._parent_trace:destroy()
      entity_struct._parent_trace = nil
   end
   if entity_struct._location_trace then
      entity_struct._location_trace:destroy()
      entity_struct._location_trace = nil
   end
   
   self:_remove_entity_from_graphs(entity_struct)

   -- remove all of the entity's connectors from the connector locations tables
   for type, connectors in pairs(entity_struct.connections) do
      local conn_tbl = self:get_connections(type)
      conn_tbl.entity_structs[id] = nil
      -- remove connectors from index
      for key, connector in pairs(connectors) do
         for _, clump_region_key in pairs(connector.clump_region_keys) do
            conn_tbl.connector_locations[clump_region_key][id] = nil
         end
      end
   end

   self._sv.entities[id] = nil
   self.__saved_variables:mark_changed()
end

function PlayerConnections:get_connections(type)
   local conn_tbl = self._sv.connection_tables[type]
   
   if not conn_tbl then
      conn_tbl = {type = type, entity_structs = {}, connector_locations = {}, graphs = {}}
      self._sv.connection_tables[type] = conn_tbl
      self.__saved_variables:mark_changed()
   end

   return conn_tbl
end

function PlayerConnections:_add_entity_to_graphs(entity_struct)
   -- for each connection type, determine if the entity's location is within any valid connector regions

end

function PlayerConnections:_remove_entity_from_graphs(entity_struct)

end

function PlayerConnections:_update_connector_locations(entity_struct, new_location, new_rotation)
   local old_location = entity_struct.location
   
   -- when the location is nil, request it; if it's false, it's because the entity is being removed
   if new_location == nil then
      new_location = radiant.entities.get_world_grid_location(entity_struct.entity)
   end
   -- this is done in two steps so that if rotation is specified as false, we don't need to call get_facing
   if new_rotation == nil then
      new_rotation = radiant.entities.get_facing(entity_struct.entity)
   end
   new_rotation = new_rotation or 0

   -- if we have a previous location for the entity, subtract out that location from the new one
   -- so we can do a single modification to each connector region
   -- TODO: need to account for entity rotation, which could change the world location of connectors
   --    adjusting this would need to happen between the two translations

   for type, connectors in pairs(entity_struct.connections) do
      local conn_locs = self:get_connections(type).connector_locations
      
      for _, connector in pairs(connectors) do
         local r = connector.region
         if old_location then
            r = r:translated(Point3.zero - old_location)
         end
         connector.region = region_utils.rotate(r, new_rotation, Point3.zero, new_location)

         -- remove old connector location keys
         for _, key in pairs(connector.clump_region_keys) do
            conn_locs[key][entity_struct.id] = nil
         end

         connector.clump_region_keys = self:_get_region_keys(connector.region)

         -- add in new connector location keys
         for _, key in pairs(connector.clump_region_keys) do
            if not conn_locs[key] then
               conn_locs[key] = {}
            end
            conn_locs[key][entity_struct.id] = entity_struct
         end
      end
   end
end

-- get all the region group keys that a particular cube intersects
-- these are 
function PlayerConnections:_get_region_keys(cube)
   local keys = {}
   local min = cube.min
   local max = cube.max
   local clump_region_size = self._sv.clump_region_size
   for x = math.floor(min.x/clump_region_size), math.floor(max.x/clump_region_size) do
      for y = math.floor(min.y/clump_region_size), math.floor(max.y/clump_region_size) do
         for z = math.floor(min.z/clump_region_size), math.floor(max.z/clump_region_size) do
            table.insert(keys, string.format('%f,%f,%f', x, y, z))
         end
      end
   end
   return keys
end

return PlayerConnections