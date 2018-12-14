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

local ConnectionUtils = require 'lib.connection.connection_utils'

local log = radiant.log.create_logger('player_connections')

local PlayerConnections = class()

local rotate_region = ConnectionUtils.rotate_region
local combine_tables = ConnectionUtils.combine_tables
local combine_type_tables = ConnectionUtils.combine_type_tables
local _update_connection_data = ConnectionUtils._update_connection_data

function PlayerConnections:__init()
   
end

function PlayerConnections:initialize()
   self._sv.chunk_region_size = 8
   self._entities = {} -- list of all the entities being tracked: [entity id]{id, entity, (location,) connections}
   -- connections: [type]{(entity_id,) (type,) max_connections, (num_connections,) connectors}
   self.connectors = {} -- list of all connectors, indexed by id ("entity_id..|..type..|..connector_name")
   -- connectors: [id]{(name,) (entity_id,) (type,) (id,) max_connections, (num_connections,) region, (chunk_region_keys,) region_intersection_threshold, (connected_to)}
   self.connection_tables = {} -- list of connections by type: [type]{type, entity_connectors, connector_locations, graphs, entities_in_graphs}
   -- entity_connectors: [entity_id]{connector_1, connector_2}
   -- connector_locations: [chunk_region_key]{connector_1, connector_2}
   -- graphs: {nodes: [entity_id]{entity_id, connected_nodes}}
   -- entities_in_graphs: [entity_id]{graph_ids}
end

function PlayerConnections:create(player_id)
   self._sv.player_id = player_id
   self.__saved_variables:mark_changed()
end

function PlayerConnections:restore()
   self._is_restore = true
end

function PlayerConnections:post_activate()

end

function PlayerConnections:destroy()
   
end

function PlayerConnections:get_disconnected_entities(type)
   local entities = {}
   local count = 0
   local conn_tbl = self:get_connections(type)
   for id, _ in pairs(conn_tbl.entity_connectors) do
      if not conn_tbl.entities_in_graphs[id] then
         table.insert(entities, id)
      end
   end
   
   return entities
end

function PlayerConnections:get_connections_data(type)
   local entities = {}

   for id, entity_struct in pairs(self._entities) do
      entities[entity_struct.id] = entity_struct.entity:get_component('stonehearth_ace:connection'):get_connected_stats(type)
   end

   return entities
end

function PlayerConnections:_update_entity_changes_connector(entity, type, conn_name, connected_to_id, graph_id)
   entity:get_component('stonehearth_ace:connection'):set_connected_stats(type, conn_name, connected_to_id, graph_id)
end

function PlayerConnections:update_entity(entity_id, add_only)
   local entity_struct = self._entities[entity_id]
   local changed_types_2, graphs_changed_2

   if not add_only then
      changed_types_2, graphs_changed_2 = self:_remove_entity_from_graphs(entity_struct)
   end
   
   self:_update_connector_locations(entity_struct)
   local changed_types, graphs_changed = self:_add_entity_to_graphs(entity_struct)
   
   if not add_only then
      combine_tables(changed_types, changed_types_2)
      graphs_changed = combine_type_tables(graphs_changed, graphs_changed_2)
   end

   --self.__saved_variables:mark_changed()

   return self:_get_changes(changed_types, graphs_changed)
end

function PlayerConnections:remove_entity(entity_id)
   local entity_struct = self._entities[entity_id]
   local changed_types, graphs_changed = self:_remove_entity_from_graphs(entity_struct)
   self:_update_connector_locations(entity_struct, false, false)
   --self.__saved_variables:mark_changed()
   
   return self:_get_changes(changed_types, graphs_changed)
end

function PlayerConnections:_get_changes(changed_types, graphs_changed)
   return {
      changed_types = changed_types or {},
      graphs_changed = graphs_changed or {}
   }
end

function PlayerConnections:register_entity(entity, connections, separated_by_player, connected_stats)
   local id = entity:get_id()
   if not self._entities[id] then
      local conns = {}
      local entity_struct = {id = id, entity = entity, connections = conns, origin = entity:get_component('mob'):get_model_origin()}
      self._entities[id] = entity_struct
      
      -- organize connections by type
      for type, connection in pairs(connections) do
         if separated_by_player == stonehearth_ace.connection:is_separated_by_player(type) then
            local connection_stats = connected_stats and connected_stats[type]
            local conn_tbl = self:get_connections(type)
            if not conn_tbl.entity_connectors[id] then
               conn_tbl.entity_connectors[id] = {}
            end

            local conn = {}
            conns[type] = conn
            conn.entity_id = id
            conn.num_connections = connection_stats and connection_stats.num_connections or 0
            conn.max_connections = connection.max_connections
            conn.type = type
            conn.origin_offset = radiant.util.to_point3(connection.origin_offset) or Point3.zero
            conn.connectors = {}

            for key, connector in pairs(connection.connectors) do
               local connector_id = self:_get_entity_connector_id(id, type, key)
               conn.connectors[key] = connector_id
               conn_tbl.entity_connectors[id][connector_id] = connector_id

               local connect = self.connectors[connector_id] or {}
               connect.name = key
               connect.id = connector_id
               connect.info = connector.info
               connect.max_connections = connector.max_connections
               connect.entity_id = id
               connect.connection = type
               connect.region = connector.region
               connect.region_area = connector.region:get_area()
               connect.region_intersection_threshold = connector.region_intersection_threshold or 0
               
               connect.num_connections = connect.num_connections or 0
               connect.connected_to = connect.connected_to or {}
               connect.chunk_region_keys = connect.chunk_region_keys or {}
               
               self.connectors[connector_id] = connect

               if connection_stats then
                  local connector_stats = connection_stats.connectors[connect.name]
                  connect.num_connections = connector_stats and connector_stats.num_connections or 0
                  if connector_stats then
                     for connected_to_id, _ in pairs(connector_stats.connected_to) do
                        connect.connected_to[connected_to_id] = true
                     end
                  end
               else
                  self:_update_entity_changes_connector(entity, type, connect.name)
               end
            end
         end
      end

      if connected_stats then
         self:_update_connector_locations(entity_struct)
         self:_load_entity_graph_data(id, connected_stats, separated_by_player)
      else
         return self:update_entity(id, true)
      end
   end
end

function PlayerConnections:unregister_entity(entity)
   local id = entity:get_id()
   local entity_struct = self._entities[id]

   if entity_struct then
      local result = self:remove_entity(id)
      -- remove all of the entity's connectors from the connector locations tables
      for type, connection in pairs(entity_struct.connections) do
         local conn_tbl = self:get_connections(type)
         conn_tbl.entity_connectors[id] = nil
         -- remove connectors from index
         for key, connector_id in pairs(connection.connectors) do
            local connector = self:get_entity_connector(connector_id)
            for _, chunk_region_key in ipairs(connector.chunk_region_keys) do
               local conn_locs = conn_tbl.connector_locations[chunk_region_key]
               conn_locs[connector_id] = nil
            end
            --conn_tbl.entity_connectors[id][connector.id] = nil
         end
      end

      self._entities[id] = nil
      --self.__saved_variables:mark_changed()

      return result
   end
end

function PlayerConnections:get_connections(type)
   local conn_tbl = self.connection_tables[type]
   
   if not conn_tbl then
      conn_tbl = {type = type, entity_connectors = {}, connector_locations = {}, graphs = {}, entities_in_graphs = {}}
      self.connection_tables[type] = conn_tbl
      --self.__saved_variables:mark_changed()
   end

   return conn_tbl
end

function PlayerConnections:_get_graph(id)
   return stonehearth_ace.connection:get_graph_by_id(id)
end

function PlayerConnections:_get_graphs(graph_ids)
   local graphs = {}
   for id, _ in pairs(graph_ids) do
      graphs[id] = self:_get_graph(id)
   end
   return graphs
end

function PlayerConnections:get_entity_connector(id)
   return self.connectors[id]
end

function PlayerConnections:_get_entity_connector_id(entity_id, type, connector_name)
   return entity_id..'|'..type..'|'..connector_name
end

-- recreate graphs from each connected entity's connected stats
function PlayerConnections:_load_entity_graph_data(entity_id, connected_stats, separated_by_player)
   for type, conn_stats in pairs(connected_stats) do
      if separated_by_player == stonehearth_ace.connection:is_separated_by_player(type) then
         local conn_tbl = self:get_connections(type)
         conn_tbl.entities_in_graphs[entity_id] = conn_stats.num_connections > 0 or nil
         for name, connector in pairs(conn_stats.connectors) do
            for id, graph_id in pairs(connector.connected_to) do
               conn_tbl.graphs[graph_id] = true
               local graph = stonehearth_ace.connection:get_graph_by_id(graph_id, self._sv.player_id, type)
               --conn_data.connected_to[connected_to_id] = graph_id
               -- when this gets called for the first entity that's part of this connection, the connected_to id won't be valid
               -- so when it gets called for the second (and that id is valid), connect the nodes for both at that time
               local conn_to = self:get_entity_connector(id)
               if conn_to then
                  local conn_from = self:get_entity_connector(self:_get_entity_connector_id(entity_id, type, name))
                  local graph_entity_1 = graph.nodes[entity_id]
                  local graph_entity_2 = graph.nodes[conn_to.entity_id]
                  if not graph_entity_1 then
                     graph_entity_1 = {entity_id = entity_id, connected_nodes = {}}
                     graph.nodes[entity_id] = graph_entity_1
                  end
                  if not graph_entity_2 then
                     graph_entity_2 = {entity_id = conn_to.entity_id, connected_nodes = {}}
                     graph.nodes[conn_to.entity_id] = graph_entity_2
                  end
                  graph_entity_1.connected_nodes[graph_entity_2.entity_id] = true
                  graph_entity_2.connected_nodes[graph_entity_1.entity_id] = true
               end
            end
         end
      end
   end
end

function PlayerConnections:_add_entity_to_graphs(entity_struct, only_type, entity_id_to_ignore)
   local changed_types = {}
   local graphs_changed = {}

   -- for each connection type, determine if the entity's connector regions intersect with any other valid connector regions
   for type, connection in pairs(entity_struct.connections) do
      if not only_type or type == only_type then
         local conn_tbl = self:get_connections(type)
         
         local type_graphs = {}
         graphs_changed[type] = type_graphs

         for _, id in pairs(connection.connectors) do
            if connection.num_connections >= connection.max_connections then
               break
            end

            local connector = self:get_entity_connector(id)
            if connector.num_connections < connector.max_connections then
               local changes = self:_try_connecting_connector(conn_tbl, connection, connector, entity_id_to_ignore)
               if changes and next(changes) then
                  combine_tables(type_graphs, changes)
                  changed_types[type] = true
               end
            end
         end
      end
   end

   return changed_types, graphs_changed
end

function PlayerConnections:_remove_entity_from_graphs(entity_struct)
   local changed_types = {}
   local graphs_changed = {}

   for type, connection in pairs(entity_struct.connections) do
      local conn_tbl = self:get_connections(type)
      conn_tbl.entities_in_graphs[entity_struct.id] = nil
      
      local type_graphs = {}
      graphs_changed[type] = type_graphs

      for _, connector_id in pairs(connection.connectors) do
         local connector = self:get_entity_connector(connector_id)
         for id, _ in pairs(connector.connected_to) do
            local connected = self:get_entity_connector(id)
            local connected_entity_struct = self._entities[connected.entity_id]
            local changes = self:_try_disconnecting_connectors(connector, connected)
            if changes then
               combine_tables(type_graphs, changes)

               if next(changes) then
                  changed_types[type] = true

                  -- we're already removing *this* entity from the entities_in_graphs table, but we may also need to remove the entity it was connected to
                  if conn_tbl.entities_in_graphs[connected.entity_id] then
                     local still_in = false
                     for is_connected_id, _ in pairs(conn_tbl.entity_connectors) do
                        local ec = self:get_entity_connector(is_connected_id)
                        if ec and ec.num_connections > 0 then
                           still_in = true
                           break
                        end
                     end
                     if not still_in then
                        conn_tbl.entities_in_graphs[connected.entity_id] = nil
                     end
                  end

                  self:_update_entity_changes_connector(entity_struct.entity, type, connector.name, connected.id)
                  self:_update_entity_changes_connector(connected_entity_struct.entity, type, connected.name, connector.id)
               end

               -- when removing an entity from graphs, anything it was connected to should search for new connections
               local _, added_graphs_changed = self:_add_entity_to_graphs(connected_entity_struct, type, entity_struct.id)

               if added_graphs_changed[type] and next(added_graphs_changed[type]) then
                  combine_tables(type_graphs, added_graphs_changed[type])
               end
            end
         end
      end
   end

   return changed_types, graphs_changed
end

function PlayerConnections:_try_connecting_connector(conn_tbl, connection, connector, entity_id_to_ignore)
   local entity_struct = self._entities[connector.entity_id]
   local potential_connectors = self:_find_best_potential_connectors(connector, entity_id_to_ignore)
   local graphs_changed = {}

   for _, target_connector in ipairs(potential_connectors) do
      if connector.num_connections >= connector.max_connections or connection.num_connections >= connection.max_connections then
         return graphs_changed
      end

      local target = target_connector.connector
      local changes = self:_try_connecting_connectors(connector, target)
      if changes then
         combine_tables(graphs_changed, changes)

         if next(changes) then
            local target_entity_struct = self._entities[target.entity_id]
            local target_connection = target_entity_struct.connections[target.connection]

            conn_tbl.entities_in_graphs[connector.entity_id] = true
            conn_tbl.entities_in_graphs[target.entity_id] = true
         end
      end
   end

   return graphs_changed
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
   
   local e1 = self._entities[c1.entity_id]
   local e2 = self._entities[c2.entity_id]

   if not e1 or not e2 then
      return nil
   end

   local conn1 = e1.connections[c1.connection]
   local conn2 = e2.connections[c2.connection]

   if conn1.type ~= conn2.type or e1 == e2 then
      return nil
   end

   if c1.num_connections < c1.max_connections and c2.num_connections < c2.max_connections and
         conn1.num_connections < conn1.max_connections and conn2.num_connections < conn2.max_connections then
      
      -- we create a separate graph for each separate group of connected entities
      -- if this connection connects entities from two separate graphs, we need to merge those graphs
      local graph_indexes = self:get_connections(conn1.type).graphs
      local graphs = self:_get_graphs(graph_indexes)
      local graphs_changed = {}
      local graphs_to_merge = {}
      local graph_entity_1 = nil
      local graph_entity_2 = nil

      for id, graph in pairs(graphs) do
         if graph.nodes[e1.id] then
            graph_entity_1 = graph.nodes[e1.id]
            if graph_entity_1.connected_nodes[e2.id] then
               -- if these two entities are already connected in the same graph, this connection is redundant and should be canceled
               return false
            elseif graph.nodes[e2.id] then
               -- both entities are in the same graph, just not directly connected to one another yet
               graph_entity_2 = graph.nodes[e2.id]
            end
            table.insert(graphs_to_merge, id)
         elseif graph.nodes[e2.id] then
            graph_entity_2 = graph.nodes[e2.id]
            table.insert(graphs_to_merge, id)
         end
      end

      if not graph_entity_1 then
         graph_entity_1 = {entity_id = e1.id, connected_nodes = {}}
      end
      if not graph_entity_2 then
         graph_entity_2 = {entity_id = e2.id, connected_nodes = {}}
      end
      graph_entity_1.connected_nodes[e2.id] = true
      graph_entity_2.connected_nodes[e1.id] = true

      local graph = nil
      if #graphs_to_merge == 0 then
         graph = stonehearth_ace.connection:_create_new_graph(conn1.type, self._sv.player_id)
         graph_indexes[graph.id] = true
      else
         graph = graphs[graphs_to_merge[1]]
      end
      graphs_changed[graph.id] = true

      -- merge all additional graphs into the first one
      for i = #graphs_to_merge, 2, -1 do
         local graph_id = graphs_to_merge[i]
         for id, node in pairs(graphs[graph_id].nodes) do
            graph.nodes[id] = node
            self:_update_entity_changes_connector(self._entities[id].entity, conn1.type, nil, nil, graph.id)
         end
         stonehearth_ace.connection:_remove_graph(graph_id)
         graph_indexes[graph_id] = nil
         graphs_changed[graph_id] = true
      end

      -- make sure both newly-connected nodes are members of the current graph
      graph.nodes[e1.id] = graph_entity_1
      graph.nodes[e2.id] = graph_entity_2

      c1.connected_to[c2.id] = true
      c2.connected_to[c1.id] = true

      c1.num_connections = c1.num_connections + 1
      c2.num_connections = c2.num_connections + 1
      conn1.num_connections = conn1.num_connections + 1
      conn2.num_connections = conn2.num_connections + 1

      self:_update_entity_changes_connector(e1.entity, conn1.type, c1.name, c2.id, graph.id)
      self:_update_entity_changes_connector(e2.entity, conn1.type, c2.name, c1.id, graph.id)

      return graphs_changed
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
   
   local e1 = self._entities[c1.entity_id]
   local e2 = self._entities[c2.entity_id]

   if not e1 or not e2 then
      return nil
   end

   local conn1 = e1.connections[c1.connection]
   local conn2 = e2.connections[c2.connection]

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

   local graph_indexes = self:get_connections(conn1.type).graphs
   local graphs = self:_get_graphs(graph_indexes)
   local graphs_changed = {}

   for id, graph in pairs(graphs) do
      local n1 = graph.nodes[e1.id]
      local n2 = graph.nodes[e2.id]

      if n1 and n1.connected_nodes[e2.id] then
         n1.connected_nodes[e2.id] = nil
         if not next(n1.connected_nodes) then
            graph.nodes[e1.id] = nil
            graphs_changed[graph.id] = true
            n1 = nil
         end
      end

      if n2 and n2.connected_nodes[e1.id] then
         n2.connected_nodes[e1.id] = nil
         if not next(n2.connected_nodes) then
            graph.nodes[e2.id] = nil
            graphs_changed[graph.id] = true
            n2 = nil
         end
      end

      if not next(graph.nodes) then
         stonehearth_ace.connection:_remove_graph(graph.id)
         graph_indexes[graph.id] = nil
      end

      if n1 and n2 then
         -- they both have other connections; check recursively to see if they're still connected to one another
         -- if not, we have to split the graph
         local checked = {}
         if not self:_is_deep_connected(graph, n1, n2, checked) then
            -- remove all the nodes in [checked] from this graph and put them in a new one
            local new_graph = stonehearth_ace.connection:_create_new_graph(conn1.type, self._sv.player_id)
            graph_indexes[new_graph.id] = true
            for id, node in pairs(checked) do
               graph.nodes[id] = nil
               new_graph.nodes[id] = node
            end
            graphs_changed[graph.id] = true
            graphs_changed[new_graph.id] = true
         end
      end

      if next(graphs_changed) then
         break
      end
   end

   return graphs_changed
end

-- recursively processes through 'connected_nodes' for n1 to see if it can find n2, ignoring previously checked nodes
function PlayerConnections:_is_deep_connected(graph, n1, n2, checked)
   --log:debug('trying to split a graph')
   checked[n1.entity_id] = n1

   for n_id, _ in pairs(n1.connected_nodes) do
      if n_id == n2.entity_id then
         --log:debug('found a match: %s = %s', n_id, n2.entity_id)
         return true
      end
      if not checked[n_id] then
         if self:_is_deep_connected(graph, graph.nodes[n_id], n2, checked) then
            return true
         end
      end
   end

   return false
end

function PlayerConnections:_find_best_potential_connectors(connector, entity_id_to_ignore)
   local result = {}
   entity_id_to_ignore = entity_id_to_ignore or connector.entity_id
   
   if connector.trans_region then
      local r = connector.trans_region
      local conn_locs = self:get_connections(connector.connection).connector_locations
      
      -- we only need to check other connectors that are in region chunks that this one intersects
      for _, crk in ipairs(connector.chunk_region_keys) do
         --log:debug('testing crk %s', crk)
         for id, _ in pairs(conn_locs[crk]) do
            local conn = self:get_entity_connector(id)
            --log:debug('seeing if %s can connect to %s', connector.id, id)
            --log:debug('conn %s: %s, %s', id, conn.connection.entity_struct.id, connection.entity_struct.id)
            if conn.entity_id ~= connector.entity_id
                  and conn.entity_id ~= entity_id_to_ignore
                  and conn.num_connections < conn.max_connections and conn.trans_region then
               
               local intersection = r:intersect_region(conn.trans_region):get_area()
               --log:debug('checking intersection of connection regions %s and %s', connector.trans_region:get_bounds(), conn.trans_region:get_bounds())
               if intersection > 0 then
                  -- rank potential connectors by how closely their regions intersect
                  local rank_connector = intersection / connector.region_area
                  local rank_conn = intersection / conn.region_area
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
      
      for _, connector_id in pairs(connection.connectors) do
         local connector = self:get_entity_connector(connector_id)
         --log:debug('rotating region %s by %s°, then translating by %s', connector.region, new_rotation, new_location or '[NIL]')
         if new_location then
            connector.trans_region = rotate_region(connector.region, entity_struct.origin - connection.origin_offset, new_rotation):translated(new_location)
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
            conn_locs[key][connector.id] = true
         end
      end
   end
end

-- get all the region group keys that a particular cube intersects
function PlayerConnections:_get_region_keys(region)
   local keys = {}
   if region then
      local bounds = region:get_bounds()
      local min = bounds.min
      local max = bounds.max
      local chunk_region_size = self._sv.chunk_region_size
      for x = math.floor((min.x + 1)/chunk_region_size), math.floor(max.x/chunk_region_size) do
         for y = math.floor((min.y + 1)/chunk_region_size), math.floor(max.y/chunk_region_size) do
            for z = math.floor((min.z + 1)/chunk_region_size), math.floor(max.z/chunk_region_size) do
               table.insert(keys, string.format('%d,%d,%d', x, y, z))
            end
         end
      end
   end
   return keys
end

return PlayerConnections