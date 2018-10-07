--[[
contains collections of all "connected" entities for a player
these are grouped by connection type; entities can have multiple connection types
]]

local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local region_utils = require 'stonehearth.lib.building.region_utils'

local PlayerConnections = class()

function PlayerConnections:__init()
   
end

function PlayerConnections:initialize()
   self._sv.chunk_region_size = 8
   self._sv.entities = {} -- list of all the entities being tracked: [entity id]{id, entity, (location,) connections}
   -- connections: [type]{(entity_struct,) (type,) max_connections, (num_connections,) connectors}
   -- connectors: [name]{(connections,) max_connections, (num_connections,) region, (chunk_region_keys,) region_intersection_threshold, (connected_to)}
   self._sv.connection_tables = {} -- list of connections by type: [type]{type, entity_connectors, connector_locations, graphs}
   -- entity_connectors: [entity_id]{connector_1, connector_2}
   -- connector_locations: [chunk_region_key]{connector_1, connector_2}
   -- graphs: {nodes: [entity_id]{entity_struct, connected_nodes}}
end

function PlayerConnections:create(player_id)
   self._sv.player_id = player_id
   self.__saved_variables:mark_changed()
   self:pre_activate()
end

function PlayerConnections:restore()
   self:pre_activate()
   self._is_restore = true
end

function PlayerConnections:pre_activate()
   -- add traces for the already-registered entities
   self._traces = {}
   self:_start_all_traces()
end

function PlayerConnections:post_activate()

end

function PlayerConnections:destroy()
   self:_stop_all_traces()
end

function PlayerConnections:_start_all_traces()
   for _, entity_struct in pairs(self._sv.entities) do
      self:_start_entity_traces(entity_struct)
   end
end

function PlayerConnections:_stop_all_traces()
   for _, entity_struct in pairs(self._sv.entities) do
      self:_stop_entity_traces(entity_struct)
   end
end

function PlayerConnections:_start_entity_traces(entity_struct)
   if not self._traces[entity_struct.id] then
      local entity = entity_struct.entity
      local traces = {}
      traces._parent_trace = entity:add_component('mob'):trace_parent('connection entity added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
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
            self.__saved_variables:mark_changed()
         end)

      traces._location_trace = entity:add_component('mob'):trace_transform('connection entity moved', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
            self:_remove_entity_from_graphs(entity_struct)
            self:_update_connector_locations(entity_struct)
            self:_add_entity_to_graphs(entity_struct)
            self.__saved_variables:mark_changed()
         end)
      
      self._traces[entity_struct.id] = traces
   end
end

function PlayerConnections:_stop_entity_traces(entity_struct)
   local traces = self._traces[entity_struct.id]

   if traces then
      if traces._parent_trace then
         traces._parent_trace:destroy()
         traces._parent_trace = nil
      end
      if traces._location_trace then
         traces._location_trace:destroy()
         traces._location_trace = nil
      end

      self._traces[entity_struct.id] = nil
   end
end

function PlayerConnections:register_entity(entity, connections)
   local id = entity:get_id()
   if not self._sv.entities[id] then
      local entity_struct = {id = id, entity = entity, connections = connections}
      self._sv.entities[id] = entity_struct
      
      -- organize connections by type
      for type, connection in pairs(connections) do
         connection.entity_struct = entity_struct
         connection.num_connections = 0
         connection.type = type

         for key, connector in pairs(connection.connectors) do
            -- transform all the region JSON data into Cube3 structures
            connector.region = radiant.util.to_cube3(connector.region)

            connector.num_connections = 0
            connector.connections = connections
            connector.connected_to = {}
            connector.region_intersection_threshold = connector.region_intersection_threshold or 0
            connector.chunk_region_keys = {}
         end
         
         local conn_tbl = self:get_connections(type)
         if not conn_tbl.entity_structs[id] then
            local e = {entity_struct = entity_struct, connectors = {}}
            conn_tbl.entity_structs[id] = entity_struct
         end
      end

      self.__saved_variables:mark_changed()
   end

   self:_start_entity_traces(self._sv.entities[id])
end

function PlayerConnections:unregister_entity(entity)
   local id = entity:get_id()
   local entity_struct = self._sv.entities[id]

   if entity_struct then
      -- destroy traces
      self:_stop_entity_traces(entity_struct)

      self:_remove_entity_from_graphs(entity_struct)

      -- remove all of the entity's connectors from the connector locations tables
      for type, connection in pairs(entity_struct.connections) do
         local conn_tbl = self:get_connections(type)
         conn_tbl.entity_structs[id] = nil
         -- remove connectors from index
         for key, connector in pairs(connection.connectors) do
            for _, chunk_region_key in ipairs(connector.chunk_region_keys) do
               local conn_locs = conn_tbl.connector_locations[chunk_region_key]
               for i = #conn_locs, 1, -1 do
                  if conn_locs[i].connections.entity_struct == entity_struct then
                     table.remove(conn_locs, i)
                  end
               end
            end
         end
      end

      self._sv.entities[id] = nil
      self.__saved_variables:mark_changed()
   end
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
   -- for each connection type, determine if the entity's connector regions intersect with any other valid connector regions
   for type, connection in pairs(entity_struct.connections) do
      for _, connector in pairs(connection.connectors) do
         if connection.num_connections >= connection.max_connections then
            break
         end

         if connector.num_connections < connector.max_connections then
            local potential_connectors = self:_find_best_potential_connectors(entity_struct, type, connector)

            for _, target_connector in ipairs(potential_connectors) do
               if connection.num_connections >= connection.max_connections or connector.num_connections >= connector.max_connections then
                  break
               end

               self:_try_connecting_connectors(connector, target_connector.connector)
            end
         end
      end
   end
end

function PlayerConnections:_remove_entity_from_graphs(entity_struct)
   for type, connection in pairs(entity_struct.connections) do
      for _, connector in pairs(connection.connectors) do
         for id, connected in pairs(connector.connected_to) do
            if self:_try_disconnecting_connectors(connector, connected) then
               -- if this connection was successfully disconnected, trigger an event?

            end
         end
      end
   end
end

function PlayerConnections:_try_connecting_connector(connector)
   local connection = connector.connection
   local potential_connectors = self:_find_best_potential_connectors(entity_struct, type, connector)
   local result = nil

   for _, target_connector in ipairs(potential_connectors) do
      if connection.num_connections >= connection.max_connections or connection.num_connections >= connection.max_connections then
         return result
      end

      local connection_result = self:_try_connecting_connectors(connector, target_connector.connector)
      if connection_result then
         -- if this connection happened, trigger an event?

      end
      result = result or connection_result
   end

   return result
end

-- return value:
--    nil if the connectors can't be connected for a technical/error reason (the connectors are the same, or are part of the same entity, or are of different types)
--    false if the connectors can't be connected for normal reason (their entities are already connected, or a max_connections has been reached)
--    true if the connection succeeds
function PlayerConnections:_try_connecting_connectors(c1, c2)
   if c1 == c2 then
      return nil
   end

   if c1.connected_to[c2] or c2.connected_to[c1] then
      return nil
   end
   
   local conn1 = c1.connections
   local conn2 = c2.connections
   local e1 = conn1.entity_struct
   local e2 = conn2.entity_struct

   if conn1.type ~= conn2.type or e1 == e2 then
      return nil
   end

   if c1.num_connections < c1.max_connections and c2.num_connections < c2.max_connections and
         conn1.num_connections < conn1.max_connections and conn2.num_connections < conn2.max_connections then
      
      local graphs = self:get_connections(conn1.type).graphs
      local graphs_to_merge = {}
      local graph_entity_1 = nil
      local graph_entity_2 = nil

      for i, graph in ipairs(graphs) do
         if graph.nodes[e1.id] then
            graph_entity_1 = graph.nodes[e1.id]
            if graph_entity_1.connected_nodes[e2.id] then
               -- if these two entities are already connected in the same graph, this connection is redundant and should be canceled
               return false
            elseif graph.nodes[e2.id] then
               -- both entities are in the same graph, just not directly connected to one another yet
               graph_entity_2 = graph.nodes[e2.id]
            end
            table.insert(graphs_to_merge, i)
         elseif graph.nodes[e2.id] then
            graph_entity_2 = graph.nodes[e2.id]
            table.insert(graphs_to_merge, i)
         end
      end

      if not graph_entity_1 then
         graph_entity_1 = {entity_struct = e1, connected_nodes = {}}
      end
      if not graph_entity_2 then
         graph_entity_2 = {entity_struct = e2, connected_nodes = {}}
      end
      graph_entity_1.connected_nodes[e2.id] = graph_entity_2
      graph_entity_2.connected_nodes[e1.id] = graph_entity_1

      local graph = nil
      if #graphs_to_merge == 0 then
         graph = {nodes = {}}
         table.insert(graphs, graph)
      else
         graph = graphs[graphs_to_merge[1]]
      end

      -- merge all additional graphs into the first one
      for i = #graphs_to_merge, 2, -1 do
         for id, node in pairs(graphs[graphs_to_merge[i]].nodes) do
            graph.nodes[id] = node
         end
         table.remove(graphs, graphs_to_merge[i])
      end

      -- make sure both newly-connected nodes are members of the current graph
      graph[e1.id] = graph_entity_1
      graph[e2.id] = graph_entity_2

      c1.connected_to[c2] = true
      c2.connected_to[c1] = true

      c1.num_connections = c1.num_connections + 1
      c2.num_connections = c2.num_connections + 1
      conn1.num_connections = conn1.num_connections + 1
      conn2.num_connections = conn2.num_connections + 1

      return true
   end

   return false
end

function PlayerConnections:_try_disconnecting_connectors(c1, c2)
   if c1 == c2 then
      return nil
   end

   if not c1.connected_to[c2] or not c2.connected_to[c1] then
      return nil
   end
   
   local conn1 = c1.connections
   local conn2 = c2.connections
   local e1 = conn1.entity_struct
   local e2 = conn2.entity_struct

   if conn1.type ~= conn2.type or e1 == e2 then
      return nil
   end

   c1.connected_to[c2] = nil
   c2.connected_to[c1] = nil

   c1.num_connections = math.max(0, c1.num_connections - 1)
   c2.num_connections = math.max(0, c2.num_connections - 1)
   conn1.num_connections = math.max(0, conn1.num_connections - 1)
   conn2.num_connections = math.max(0, conn2.num_connections - 1)

   return true
end

function PlayerConnections:_find_best_potential_connectors(entity_struct, type, connector)
   local result = {}
   local conn_locs = self:get_connections(type).connector_locations
   local r = Region3(connector.region)
   -- we only need to check other connectors that are in region chunks that this one intersects
   for _, crk in ipairs(connector.chunk_region_keys) do
      for _, conn in pairs(conn_locs[crk]) do
         if conn.connections.entity_struct ~= entity_struct and conn.num_connections < conn.max_connections then
            local intersection = r:intersect_region(Region3(conn.region)):get_area()
            if intersection > 0 then
               -- rank potential connectors by how closely their regions intersect
               local rank_connector = intersection / r:get_area()
               local rank_conn = intersection / conn.region:get_area()
               -- the rank has to meet the threshold for each connector
               if rank_connector >= connector.region_intersection_threshold and rank_conn >= conn.region_intersection_threshold then
                  table.insert(result, {connector = conn, rank = rank_connector})
               end
            end
         end
      end
   end

   table.sort(result, function(v1, v2)
      return v1.rank < v2.rank
   end)
   return result
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
   -- rotate according to the entity's facing direction, then translate to the new location

   for type, connection in pairs(entity_struct.connections) do
      local conn_locs = self:get_connections(type).connector_locations
      
      for _, connector in pairs(connection.connectors) do
         local r = connector.region
         if old_location then
            r = r:translated(Point3.zero - old_location)
         end
         connector.region = region_utils.rotate(r, new_rotation, Point3.zero, new_location)

         -- remove old connector location keys
         for _, key in ipairs(connector.chunk_region_keys) do
            local chunk_conn_locs = conn_locs[key]
            for i = #chunk_conn_locs, 1, -1 do
               if chunk_conn_locs[i].connections.entity_struct == entity_struct then
                  table.remove(chunk_conn_locs, i)
               end
            end
         end

         connector.chunk_region_keys = self:_get_region_keys(connector.region)

         -- add in new connector location keys
         for _, key in ipairs(connector.chunk_region_keys) do
            if not conn_locs[key] then
               conn_locs[key] = {}
            end
            table.insert(conn_locs[key], connector)
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
   local chunk_region_size = self._sv.chunk_region_size
   for x = math.floor(min.x/chunk_region_size), math.floor(max.x/chunk_region_size) do
      for y = math.floor(min.y/chunk_region_size), math.floor(max.y/chunk_region_size) do
         for z = math.floor(min.z/chunk_region_size), math.floor(max.z/chunk_region_size) do
            table.insert(keys, string.format('%f,%f,%f', x, y, z))
         end
      end
   end
   return keys
end

return PlayerConnections