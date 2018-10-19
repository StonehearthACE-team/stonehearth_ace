--[[
contains collections of all "connected" entities for a player
these are grouped by connection type; entities can have multiple connection types

Connection Rules:
   - an entity cannot directly connect to itself
   - an entity cannot directly connect to another entity with more than one connection
   - a connection must involve precisely two connectors
]]

local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
--local region_utils = require 'stonehearth.lib.building.region_utils'
local log = radiant.log.create_logger('connection')

local PlayerConnections = class()

-- basically taken from 'stonehearth.lib.building.region_utils.rotate(...)'
local MIDDLE_OFFSET = Point3(0.5, 0, 0.5)
local rotate_region = function(region, origin, rotation)
   return region:translated(origin - MIDDLE_OFFSET):rotated(rotation):translated(MIDDLE_OFFSET - origin)
end

function PlayerConnections:__init()
   
end

function PlayerConnections:initialize()
   self._sv.chunk_region_size = 8
   self._sv.entities = {} -- list of all the entities being tracked: [entity id]{id, entity, (location,) connections}
   -- connections: [type]{(entity_struct,) (type,) max_connections, (num_connections,) connectors}
   -- connectors: [name]{(name,) (connection,) max_connections, (num_connections,) region, (chunk_region_keys,) region_intersection_threshold, (connected_to)}
   self._sv.connection_tables = {} -- list of connections by type: [type]{type, entity_connectors, connector_locations, graphs}
   -- entity_connectors: [entity_id]{connector_1, connector_2}
   -- connector_locations: [chunk_region_key]{connector_1, connector_2}
   -- graphs: {nodes: [entity_id]{entity_struct, connected_nodes}}
   self._sv.connections = {}
   self._sv.connections_ds = radiant.create_datastore()
   self._sv.connections_ds:set_data({})
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

function PlayerConnections:get_connections_datastore()
   return self._sv.connections_ds
end

function PlayerConnections:_connections_updated(changed_types)
   self._sv.connections_ds:set_data(self._sv.connections)
   for type, _ in pairs(changed_types) do
      -- this could be improved to be more specific so the systems using it don't have to think/search too much
      radiant.events.trigger(self, 'stonehearth_ace:connections:'..type..':changed')
   end
end

function PlayerConnections:_update_connection_for_datastore(type, conn_id, connected)
   local conns = self._sv.connections[type]
   if conns then
      conns[conn_id] = connected or nil
   end
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
               self.__saved_variables:mark_changed()
            else
               --we were just added to the world
               -- this will get handled by the trace_transform
               --self:_update_connector_locations(entity_struct)
               --self:_add_entity_to_graphs(entity_struct)
            end
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
      local conns = {}
      local entity_struct = {id = id, entity = entity, connections = conns, origin = entity:get_component('mob'):get_model_origin()}
      self._sv.entities[id] = entity_struct
      
      -- organize connections by type
      for type, connection in pairs(connections) do
         local conn = {}
         conns[type] = conn
         conn.entity_struct = entity_struct
         conn.num_connections = 0
         conn.max_connections = connection.max_connections
         conn.type = type
         conn.connectors = {}

         for key, connector in pairs(connection.connectors) do
            local connect = {}
            conn.connectors[key] = connect
            connect.name = key
            connect.id = id..'|'..key
            connect.info = connector.info
            connect.num_connections = 0
            connect.max_connections = connector.max_connections
            connect.connection = conn
            connect.connected_to = {}
            connect.region = Cube3(connector.region)
            connect.region_intersection_threshold = connector.region_intersection_threshold or 0
            connect.chunk_region_keys = {}
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
               conn_locs[connector.id] = nil
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
      self._sv.connections[type] = {}
      self.__saved_variables:mark_changed()
   end

   return conn_tbl
end

function PlayerConnections:_add_entity_to_graphs(entity_struct)
   local changed_types = {}
   -- for each connection type, determine if the entity's connector regions intersect with any other valid connector regions
   for type, connection in pairs(entity_struct.connections) do
      for _, connector in pairs(connection.connectors) do
         if connection.num_connections >= connection.max_connections then
            break
         end

         if connector.num_connections < connector.max_connections and self:_try_connecting_connector(connector) then
            changed_types[type] = true
         end
      end
   end

   if next(changed_types) then
      self:_connections_updated(changed_types)
   end
end

function PlayerConnections:_remove_entity_from_graphs(entity_struct)
   local changed_types = {}
   for type, connection in pairs(entity_struct.connections) do
      for _, connector in pairs(connection.connectors) do
         for id, connected in pairs(connector.connected_to) do
            if self:_try_disconnecting_connectors(connector, connected) then
               changed_types[type] = true
               self:_update_connection_for_datastore(type, connector.id, false)
               self:_update_connection_for_datastore(type, connected.id, false)
            end
         end
      end
   end

   if next(changed_types) then
      self:_connections_updated(changed_types)
   end
end

function PlayerConnections:_try_connecting_connector(connector)
   local connection = connector.connection
   local potential_connectors = self:_find_best_potential_connectors(connection, connector)
   local result = false

   for _, target_connector in ipairs(potential_connectors) do
      if connector.num_connections >= connector.max_connections or connection.num_connections >= connection.max_connections then
         return result
      end

      if self:_try_connecting_connectors(connector, target_connector.connector) then
         result = true
         self:_update_connection_for_datastore(connection.type, connector.id, true)
         self:_update_connection_for_datastore(connection.type, target_connector.connector.id, true)
      end
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

   if c1.connected_to[c2.id] or c2.connected_to[c1.id] then
      return nil
   end
   
   local conn1 = c1.connection
   local conn2 = c2.connection
   local e1 = conn1.entity_struct
   local e2 = conn2.entity_struct

   if conn1.type ~= conn2.type or e1 == e2 then
      return nil
   end

   if c1.num_connections < c1.max_connections and c2.num_connections < c2.max_connections and
         conn1.num_connections < conn1.max_connections and conn2.num_connections < conn2.max_connections then
      
      -- we create a separate graph for each separate group of connected entities
      -- if this connection connects entities from two separate graphs, we need to merge those graphs
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
      graph.nodes[e1.id] = graph_entity_1
      graph.nodes[e2.id] = graph_entity_2

      c1.connected_to[c2.id] = c2
      c2.connected_to[c1.id] = c1

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

   if not c1.connected_to[c2.id] or not c2.connected_to[c1.id] then
      return nil
   end
   
   local conn1 = c1.connection
   local conn2 = c2.connection
   local e1 = conn1.entity_struct
   local e2 = conn2.entity_struct

   if conn1.type ~= conn2.type or e1 == e2 then
      return nil
   end

   c1.connected_to[c2.id] = nil
   c2.connected_to[c1.id] = nil

   c1.num_connections = math.max(0, c1.num_connections - 1)
   c2.num_connections = math.max(0, c2.num_connections - 1)
   conn1.num_connections = math.max(0, conn1.num_connections - 1)
   conn2.num_connections = math.max(0, conn2.num_connections - 1)

   -- check if there are any entities still connected to c1 and c2's entity structs
   -- if there aren't any for one or both, remove them from the graphs
   -- if there remain connections for both, check to see if they're still connected in a roundabout way:
   -- process through the 'connected_nodes' of es1 and see if it reaches es2
   -- if not, remove c1 and all connections it has to a new graph

   local graphs = self:get_connections(conn1.type).graphs
   for _, graph in ipairs(graphs) do
      local n1 = graph.nodes[e1.id]
      local n2 = graph.nodes[e2.id]

      if n1 then
         n1.connected_nodes[e2.id] = nil
         if not next(n1.connected_nodes) then
            graph.nodes[e1.id] = nil
            n1 = nil
         end
      end

      if n2 then
         n2.connected_nodes[e1.id] = nil
         if not next(n2.connected_nodes) then
            graph.nodes[e2.id] = nil
            n2 = nil
         end
      end

      if n1 and n2 then
         -- they both have other connections; check recursively to see if they're still connected to one another
         -- if not, we have to split the graph
         local checked = {}
         if not self:_is_deep_connected(n1, n1, n2, checked) then
            -- remove all the nodes in [checked] from this graph and put them in a new one
            local new_graph = {nodes = {}}
            table.insert(graphs, new_graph)
            for id, node in pairs(checked) do
               graph.nodes[id] = nil
               new_graph.nodes[id] = node
            end
         end
      end
   end

   return true
end

-- recursively processes through 'connected_nodes' for n1 to see if it can find n2, ignoring previously checked nodes
function PlayerConnections:_is_deep_connected(n_orig, n1, n2, checked)
   checked[n.entity_struct.id] = n1

   for _, n in pairs(n1.connected_nodes) do
      if n_orig == n then
         return true
      end
      if not checked[n.entity_struct.id] then
         if self:_is_deep_connected(n_orig, n, n2, checked) then
            return true
         end
      end
   end

   return false
end

function PlayerConnections:_find_best_potential_connectors(connection, connector)
   local result = {}
   
   if connector.trans_region then
      local r = Region3(connector.trans_region)
      local conn_locs = self:get_connections(connection.type).connector_locations
      
      -- we only need to check other connectors that are in region chunks that this one intersects
      for _, crk in ipairs(connector.chunk_region_keys) do
         --log:debug('testing crk %s', crk)
         for id, conn in pairs(conn_locs[crk]) do
            --log:debug('seeing if %s can connect to %s', connector.id, id)
            --log:debug('conn %s: %s, %s', id, conn.connection.entity_struct.id, connection.entity_struct.id)
            if conn.connection.entity_struct.id ~= connection.entity_struct.id and conn.num_connections < conn.max_connections and conn.trans_region then
               local intersection = r:intersect_region(Region3(conn.trans_region)):get_area()
               --log:debug('checking intersection of connection regions %s and %s', connector.trans_region, conn.trans_region)
               if intersection > 0 then
                  -- rank potential connectors by how closely their regions intersect
                  local rank_connector = intersection / r:get_area()
                  local rank_conn = intersection / conn.trans_region:get_area()
                  --log:debug('they intersect! %s and %s', rank_connector, rank_conn)
                  -- the rank has to meet the threshold for each connector
                  if rank_connector >= connector.region_intersection_threshold and rank_conn >= conn.region_intersection_threshold then
                     table.insert(result, {connector = conn, rank = rank_connector})
                  end
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
   -- when the location is nil, request it; if it's false, it's because the entity is being removed
   if new_location == nil then
      new_location = radiant.entities.get_world_grid_location(entity_struct.entity)
   end
   -- this is done in two steps so that if rotation is specified as false, we don't need to call get_facing
   if new_rotation == nil then
      new_rotation = radiant.entities.get_facing(entity_struct.entity)
   end
   new_rotation = (new_rotation and (new_rotation % 360 + 360) % 360) or 0

   -- rotate according to the entity's facing direction, then translate to the new location

   for type, connection in pairs(entity_struct.connections) do
      local conn_locs = self:get_connections(type).connector_locations
      
      for _, connector in pairs(connection.connectors) do
         --log:debug('rotating region %s by %s°, then translating by %s', connector.region, new_rotation, new_location or '[NIL]')
         if new_location then
            connector.trans_region = rotate_region(connector.region, entity_struct.origin, new_rotation):translated(new_location)
         else
            connector.trans_region = nil
         end
         --log:debug('resulting region: %s', connector.trans_region or '[NIL]')

         -- remove old connector location keys
         for _, key in ipairs(connector.chunk_region_keys) do
            conn_locs[key][connector.id] = nil
         end

         connector.chunk_region_keys = self:_get_region_keys(connector.trans_region)

         -- add in new connector location keys
         for _, key in ipairs(connector.chunk_region_keys) do
            --log:debug('adding crk %s for entity %s connector %s', key, entity_struct.id, connector.name)
            if not conn_locs[key] then
               conn_locs[key] = {}
            end
            conn_locs[key][connector.id] = connector
         end
      end
   end
end

-- get all the region group keys that a particular cube intersects
-- these are 
function PlayerConnections:_get_region_keys(cube)
   local keys = {}
   if cube then
      local min = cube.min
      local max = cube.max
      local chunk_region_size = self._sv.chunk_region_size
      for x = math.floor(min.x/chunk_region_size), math.floor(max.x/chunk_region_size) do
         for y = math.floor(min.y/chunk_region_size), math.floor(max.y/chunk_region_size) do
            for z = math.floor(min.z/chunk_region_size), math.floor(max.z/chunk_region_size) do
               table.insert(keys, string.format('%d,%d,%d', x, y, z))
            end
         end
      end
   end
   return keys
end

return PlayerConnections