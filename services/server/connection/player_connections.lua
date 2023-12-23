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

local _chunk_region_size = 5

function PlayerConnections:initialize()
   self._entities = {} -- list of all the entities being tracked: [entity id]{id, entity, (location,) connections}
   -- connections: [type]{(entity_id,) (type,) max_connections, (num_connections,) connectors}
   self._connectors = {} -- list of all connectors, indexed by id ("entity_id..|..type..|..connector_name")
   -- connectors: [id]{(name,) (entity_id,) (type,) (id,) max_connections, (num_connections,) region, (chunk_region_keys,) region_intersection_threshold, (connected_to)}
   self._connection_tables = {} -- list of connections by type: [type]{type, entity_connectors, connector_locations, graphs, entities_in_graphs}
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

function PlayerConnections:get_disconnected_entities(conn_type)
   local entities = {}
   local count = 0
   local conn_tbl = self:get_connections(conn_type)
   for id, _ in pairs(conn_tbl.entity_connectors) do
      if not conn_tbl.entities_in_graphs[id] then
         table.insert(entities, id)
      end
   end
   
   return entities
end

function PlayerConnections:get_connections_data(conn_type)
   local entities = {}

   for id, entity_struct in pairs(self._entities) do
      entities[entity_struct.id] = entity_struct.entity:get_component('stonehearth_ace:connection'):get_connected_stats(conn_type)
   end

   return entities
end

function PlayerConnections:_update_entity_changes_connector(entity, conn_type, conn_name, connected_to_id, graph_id, threshold)
   if entity and entity:is_valid() then
      entity:get_component('stonehearth_ace:connection'):set_connected_stats(conn_type, conn_name, connected_to_id, graph_id, threshold)

      if connected_to_id then
         radiant.events.trigger(entity, 'stonehearth_ace:connection:'..conn_type..':connection_changed',
            {
               connection_name = conn_name,
               connected_to_id = connected_to_id,
               connected_to_entity = self:get_entity_from_connector(connected_to_id),
               threshold = threshold
            })
      elseif graph_id then
         radiant.events.trigger(entity, 'stonehearth_ace:connection:'..conn_type..':graph_changed',
            {
               new_graph_id = graph_id
            })
      end
   end
end

function PlayerConnections:update_entity(entity_id, add_only, only_type, only_connector)
   local entity_struct = self._entities[entity_id]
   
   if entity_struct then
      local changed_types_2, graphs_changed_2

      if not add_only then
         --log:debug('update_entity not add_only')
         changed_types_2, graphs_changed_2 = self:_remove_entity_from_graphs(entity_struct)
      end
      
      --log:debug('adding %s to graphs', entity_id)
      self:_update_connector_locations(entity_struct, nil, nil, only_type, only_connector)
      local changed_types, graphs_changed = self:_add_entity_to_graphs(entity_struct, only_type)
      
      if not add_only then
         combine_tables(changed_types, changed_types_2)
         graphs_changed = combine_type_tables(graphs_changed, graphs_changed_2)
      end

      --self.__saved_variables:mark_changed()

      return self:_get_changes(changed_types, graphs_changed)
   end
end

function PlayerConnections:remove_entity(entity_id)
   local entity_struct = self._entities[entity_id]
   if entity_struct then
      --log:debug('remove_entity %s', entity_id)
      local changed_types, graphs_changed = self:_remove_entity_from_graphs(entity_struct)
      self:_update_connector_locations(entity_struct, false, false)
      --self.__saved_variables:mark_changed()
      
      return self:_get_changes(changed_types, graphs_changed)
   end
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
      -- check if there are any connection types that are actually valid for this entity; otherwise we don't need to add it here
      local has_valid_connections = false
      for conn_type, connection in pairs(connections) do
         if not separated_by_player == not stonehearth_ace.connection:is_separated_by_player(conn_type) then
            has_valid_connections = true
            break
         end
      end
      if not has_valid_connections then
         return
      end

      local conns = {}
      --local align_to_grid = radiant.array_to_map(radiant.entities.get_component_data(entity, 'mob').align_to_grid or {})
      local entity_struct = {
         id = id,
         entity = entity,
         connections = conns,
         --align_x = align_to_grid.x and true,
         --align_z = align_to_grid.z and true
      }
      self._entities[id] = entity_struct
      
      -- organize connections by type
      for conn_type, connection in pairs(connections) do
         if not separated_by_player == not stonehearth_ace.connection:is_separated_by_player(conn_type) then
            local connection_stats = connected_stats and connected_stats[conn_type]
            local conn_tbl = self:get_connections(conn_type)
            if not conn_tbl.entity_connectors[id] then
               conn_tbl.entity_connectors[id] = {}
            end

            local conn = {}
            conns[conn_type] = conn
            conn.entity_id = id
            conn.num_connections = connection_stats and connection_stats.num_connections or 0
            conn.max_connections = connection.max_connections
            conn.type = conn_type
            --conn.origin_offset = radiant.util.to_point3(connection.origin_offset) or Point3.zero
            conn.connectors = {}

            for key, connector in pairs(connection.connectors) do
               local connector_id = self:_get_entity_connector_id(id, conn_type, key)
               local connect = self:_register_connector(entity, conn_type, connection.max_connections, key, connector_id, connector)

               if connection_stats then
                  local connector_stats = connection_stats.connectors[connect.name]
                  connect.num_connections = connector_stats and connector_stats.num_connections or 0
                  if connector_stats then
                     for connected_to_id, connected in pairs(connector_stats.connected_to) do
                        connect.connected_to[connected_to_id] = connected.threshold or 0
                     end
                  end
               else
                  self:_update_entity_changes_connector(entity, conn_type, connect.name)
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

function PlayerConnections:_ensure_entity_struct(entity)
   local id = entity:get_id()
   if not self._entities[id] then
      local entity_struct = {
         id = id,
         entity = entity,
         connections = {}
      }
      self._entities[id] = entity_struct
   end
end

function PlayerConnections:_register_connector(entity, conn_type, connection_max_connections, name, connector_id, connector)
   self:_ensure_entity_struct(entity)
   local entity_id = entity:get_id()
   local es = self:get_entity_struct(entity_id)
   local conn_tbl = self:get_connections(conn_type)
   if not conn_tbl.entity_connectors[entity_id] then
      conn_tbl.entity_connectors[entity_id] = {}
   end

   local conn = es.connections[conn_type]
   if not conn then
      conn = {
         entity_id = entity_id,
         num_connections = 0,
         max_connections = connection_max_connections,
         type = conn_type,
         connectors = {}
      }
      es.connections[conn_type] = conn
   end

   conn.connectors[name] = connector_id
   conn_tbl.entity_connectors[entity_id][connector_id] = connector_id

   local connect = self._connectors[connector_id] or {}
   connect.name = name
   connect.id = connector_id
   connect.info = connector.info
   connect.max_connections = connector.max_connections
   connect.entity_id = entity_id
   connect.connection = conn_type
   connect.region = connector.region
   connect.region_area = connector.region and connector.region:get_area() or 0
   connect.region_intersection_threshold = connector.region_intersection_threshold or 0
   
   connect.num_connections = connect.num_connections or 0
   connect.connected_to = connect.connected_to or {}
   connect.chunk_region_keys = connect.chunk_region_keys or {}
   
   self._connectors[connector_id] = connect

   log:debug('registered connector %s with region %s', connector_id, connect.region and connect.region:get_bounds() or '[nil]')

   return connect
end

function PlayerConnections:unregister_entity(entity)
   local id = entity:get_id()
   local entity_struct = self._entities[id]

   if entity_struct then
      local result = self:remove_entity(id)
      -- remove all of the entity's connectors from the connector locations tables
      for conn_type, connection in pairs(entity_struct.connections) do
         local conn_tbl = self._connection_tables[conn_type]
         if conn_tbl then
            conn_tbl.entity_connectors[id] = nil
            -- remove connectors from index
            for key, connector_id in pairs(connection.connectors) do
               local connector = self._connectors[connector_id]
               for _, chunk_region_key in ipairs(connector.chunk_region_keys) do
                  local conn_locs = conn_tbl.connector_locations[chunk_region_key]
                  conn_locs[connector_id] = nil
               end
               --conn_tbl.entity_connectors[id][connector.id] = nil
            end
         end
      end

      self._entities[id] = nil
      --self.__saved_variables:mark_changed()

      return result
   end
end

-- used for adding or updating the specs of a dynamic connector
function PlayerConnections:update_connector(entity, conn_type, connection_max_connections, name, connector)
   local entity_id = entity:get_id()
   local entity_struct = self:get_entity_struct(entity_id)
   local id = self:_get_entity_connector_id(entity_id, conn_type, name)
   -- local c = self:get_entity_connector(id)
   -- local changed_types_2, graphs_changed_2
   -- if c then
   --    changed_types_2, graphs_changed_2 = self:_remove_entity_from_graphs(entity_struct, conn_type, name)
   -- end

   self:_register_connector(entity, conn_type, connection_max_connections, name, id, connector)
   
   local changed_types, graphs_changed = self:update_entity(entity_id, false, conn_type, id)
   -- if c then
   --    combine_tables(changed_types, changed_types_2)
   --    graphs_changed = combine_type_tables(graphs_changed, graphs_changed_2)
   -- end
   return self:_get_changes(changed_types, graphs_changed)
end

function PlayerConnections:remove_connector(entity, conn_type, name)
   local changed_types, graphs_changed
   local entity_id = entity:get_id()
   local entity_struct = self:get_entity_struct(entity_id)
   local id = self:_get_entity_connector_id(entity_id, conn_type, name)
   local c = self:get_entity_connector(id)
   if c then
      changed_types, graphs_changed = self:_remove_entity_from_graphs(entity_struct, conn_type, name)
      self._connectors[id] = nil

      local conn_tbl = self._connection_tables[conn_type]
      if conn_tbl then
         conn_tbl.entity_connectors[id] = nil

         for _, chunk_region_key in ipairs(c.chunk_region_keys) do
            local conn_locs = conn_tbl.connector_locations[chunk_region_key]
            conn_locs[id] = nil
         end
      end
   end

   return self:_get_changes(changed_types, graphs_changed)
end

function PlayerConnections:get_connections(conn_type)
   local conn_tbl = self._connection_tables[conn_type]
   
   if not conn_tbl then
      conn_tbl = {
         type = conn_type,
         connector_locations = {},
         entity_connectors = {},
         maintain_graphs = stonehearth_ace.connection:should_maintain_graphs(conn_type),
         graphs = {},
         entities_in_graphs = {}
      }
      self._connection_tables[conn_type] = conn_tbl
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
      graphs[id] = stonehearth_ace.connection:get_graph_by_id(id)
   end
   return graphs
end

function PlayerConnections:get_entity_struct(id)
   return self._entities[id]
end

function PlayerConnections:get_entity_connector(id)
   return self._connectors[id]
end

function PlayerConnections:get_entity_from_connector(id)
   local conn = id and self._connectors[id]
   local entity_id = conn and conn.entity_id
   local entity_struct = entity_id and self._entities[entity_id]
   return entity_struct and entity_struct.entity
end

function PlayerConnections:_get_entity_connector_id(entity_id, conn_type, connector_name)
   return entity_id..'|'..conn_type..'|'..connector_name
end

-- recreate graphs from each connected entity's connected stats
function PlayerConnections:_load_entity_graph_data(entity_id, connected_stats, separated_by_player)
   for conn_type, conn_stats in pairs(connected_stats) do
      if separated_by_player == stonehearth_ace.connection:is_separated_by_player(conn_type) then
         local conn_tbl = self:get_connections(conn_type)
         for name, connector in pairs(conn_stats.connectors) do
            for id, graph_connection in pairs(connector.connected_to) do
               -- connected_to now stores a table with graph_id and threshold instead of just storing the graph_id
               local graph_id = radiant.util.is_a(graph_connection, 'table') and graph_connection.graph_id
               if graph_id then
                  conn_tbl.entities_in_graphs[entity_id] = graph_id
                  conn_tbl.graphs[graph_id] = true
                  local graph = stonehearth_ace.connection:get_graph_by_id(graph_id, self._sv.player_id, conn_type)
                  --conn_data.connected_to[connected_to_id] = graph_id
                  -- when this gets called for the first entity that's part of this connection, the connected_to id won't be valid
                  -- so when it gets called for the second (and that id is valid), connect the nodes for both at that time
                  local conn_to = self._connectors[id]
                  if conn_to then
                     local conn_from = self._connectors[self:_get_entity_connector_id(entity_id, conn_type, name)]
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
end

function PlayerConnections:_add_entity_to_graphs(entity_struct, only_type, entity_id_to_ignore)
   local changed_types = {}
   local graphs_changed = {}

   if entity_struct then
      -- for each connection type, determine if the entity's connector regions intersect with any other valid connector regions
      for conn_type, connection in pairs(entity_struct.connections) do
         if not only_type or conn_type == only_type then
            local conn_tbl = self:get_connections(conn_type)
            
            local type_graphs = {}
            graphs_changed[conn_type] = type_graphs

            -- find the best connections for all connectors of this type
            local possible_connections = self:_find_best_potential_connections(connection, entity_id_to_ignore)
            --log:debug('possible connections for %s[%s]: %s', entity_struct.entity, type, radiant.util.table_tostring(possible_connections))

            -- go through in order (resulting sequence is sorted)
            for _, possible_connection in ipairs(possible_connections) do
               local changes = self:_try_connecting_connectors(possible_connection)
               if changes then
                  changed_types[conn_type] = true
                  if next(changes) then
                     combine_tables(type_graphs, changes)
                  end
               end
            end
         end
      end
   end

   return changed_types, graphs_changed
end

function PlayerConnections:_remove_entity_from_graphs(entity_struct, only_type, only_connector)
   local changed_types = {}
   local graphs_changed = {}

   if entity_struct then
      for conn_type, connection in pairs(entity_struct.connections) do
         if not only_type or conn_type == only_type then
            local conn_tbl = self:get_connections(conn_type)
            local graph_id = conn_tbl.entities_in_graphs[entity_struct.id]
            conn_tbl.entities_in_graphs[entity_struct.id] = nil
            
            local type_graphs = {}
            graphs_changed[conn_type] = type_graphs

            local connected_entities = {}
            
            for _, connector_id in pairs(connection.connectors) do
               local connector = self._connectors[connector_id]
               if not only_connector or connector.name == only_connector then
                  local connected_to = radiant.keys(connector.connected_to)
                  for _, id in ipairs(connected_to) do
                     --log:debug('trying to disconnect %s from %s', connector_id, id)
                     local connected = self._connectors[id]
                     connected_entities[connected.entity_id] = true
                     local connected_entity_struct = self._entities[connected.entity_id]
                     local changes = self:_try_disconnecting_connectors(connector, connected, true)
                     if changes then
                        if next(changes) then
                           combine_tables(type_graphs, changes)
                        end

                        changed_types[conn_type] = true

                        if conn_tbl.maintain_graphs then
                           -- we're already removing *this* entity from the entities_in_graphs table, but we may also need to remove the entity it was connected to
                           if conn_tbl.entities_in_graphs[connected.entity_id] then
                              local still_in = false
                              for is_connected_id, _ in pairs(conn_tbl.entity_connectors) do
                                 local ec = self._connectors[is_connected_id]
                                 if ec and ec.num_connections > 0 then
                                    still_in = true
                                    break
                                 end
                              end
                              if not still_in then
                                 conn_tbl.entities_in_graphs[connected.entity_id] = nil
                              end
                           end
                        end

                        -- when removing an entity from graphs, anything it was connected to should search for new connections
                        local _, added_graphs_changed = self:_add_entity_to_graphs(connected_entity_struct, conn_type, entity_struct.id)

                        if added_graphs_changed[conn_type] and next(added_graphs_changed[conn_type]) then
                           combine_tables(type_graphs, added_graphs_changed[conn_type])
                        end
                     end
                  end
               end
            end

            if graph_id then
               local graph = stonehearth_ace.connection:get_graph_by_id(graph_id)
               if graph then
                  local changes = self:_split_graph_deep_disconnected(conn_tbl.graphs, graph, connected_entities)
                  if changes then
                     combine_tables(type_graphs, changes)
                  end
               end
            end
         end
      end
   end

   return changed_types, graphs_changed
end

-- return value:
--    nil if the connectors can't be connected for a technical/error reason (the connectors are the same, or are part of the same entity, or are of different types)
--    false if the connectors can't be connected for normal reason (their entities are already connected, or a max_connections has been reached)
--    the graphs changed if the connection succeeds
function PlayerConnections:_try_connecting_connectors(potential_connection)
   local c1 = potential_connection.connector
   local c2 = potential_connection.target_connector
   
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

   local graphs_changed
   local connectors_disconnected = {}

   local conn_tbl = self:get_connections(conn1.type)
   local connected_graph_id

   -- the current connector or the target connector might already have reached their max_connections
   -- however, if the new potential connection outranks their lowest ranked current connection, we want to override it
   if c1.num_connections >= c1.max_connections then
      local worst_id, worst_rank = self:_get_worst_connection(c1)
      if worst_id then
         if worst_rank >= potential_connection.this_rank then
            return false
         else
            --log:debug('found a better connection: %s + %s (%s / %s) => %s + %s (%s / %s)',
            --   c1.id, worst_id, c1.connected_to[worst_id], worst_rank,
            --   c1.id, c2.id, potential_connection.this_rank, potential_connection.target_rank)
            connectors_disconnected[c1] = self._connectors[worst_id]
         end
      end
   end
   if c2.num_connections >= c2.max_connections then
      local worst_id, worst_rank = self:_get_worst_connection(c2)
      if worst_id then
         if worst_rank >= potential_connection.target_rank then
            return false
         else
            --log:debug('found a better connection: %s + %s (%s / %s) => %s + %s (%s / %s)',
            --   c2.id, worst_id, c2.connected_to[worst_id], worst_rank,
            --   c2.id, c1.id, potential_connection.target_rank, potential_connection.this_rank)
            connectors_disconnected[c2] = self._connectors[worst_id]
         end
      end
   end

   for dc1, dc2 in pairs(connectors_disconnected) do
      --log:debug('diconnecting %s and %s because a better connection was found', dc1.id, dc2.id)
      local changes = self:_try_disconnecting_connectors(dc1, dc2)
      if changes then
         if not graphs_changed then
            graphs_changed = {}
         end
         combine_tables(graphs_changed, changes)
      end
   end

   if c1.num_connections < c1.max_connections and c2.num_connections < c2.max_connections and
         conn1.num_connections < conn1.max_connections and conn2.num_connections < conn2.max_connections then
      
      if not graphs_changed then
         graphs_changed = {}
      end

      if conn_tbl.maintain_graphs then
         -- we create a separate graph for each separate group of connected entities
         -- if this connection connects entities from two separate graphs, we need to merge those graphs
         local graph_indexes = conn_tbl.graphs
         local graphs = self:_get_graphs(graph_indexes)
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
         if #graphs_to_merge > 0 then
            graph = graphs[graphs_to_merge[1]]
         end
         if not graph then
            graph = stonehearth_ace.connection:_create_new_graph(conn1.type, self._sv.player_id)
            graph_indexes[graph.id] = true
         end
         graphs_changed[graph.id] = true

         -- merge all additional graphs into the first one
         for i = #graphs_to_merge, 2, -1 do
            local graph_id = graphs_to_merge[i]
            --log:debug('merging graphs %s and %s', graph_id, graph.id)
            for id, node in pairs(graphs[graph_id] and graphs[graph_id].nodes or {}) do
               graph.nodes[id] = node
               local e = self._entities[id]
               if e then
                  self:_update_entity_changes_connector(e.entity, conn1.type, nil, nil, graph.id)
               end
            end
            stonehearth_ace.connection:_remove_graph(graph_id)
            graph_indexes[graph_id] = nil
            graphs_changed[graph_id] = true
         end

         -- make sure both newly-connected nodes are members of the current graph
         graph.nodes[e1.id] = graph_entity_1
         graph.nodes[e2.id] = graph_entity_2

         connected_graph_id = graph.id
         conn_tbl.entities_in_graphs[e1.id] = connected_graph_id
         conn_tbl.entities_in_graphs[e2.id] = connected_graph_id
      end

      c1.connected_to[c2.id] = potential_connection.this_rank
      c2.connected_to[c1.id] = potential_connection.target_rank

      c1.num_connections = c1.num_connections + 1
      c2.num_connections = c2.num_connections + 1
      conn1.num_connections = conn1.num_connections + 1
      conn2.num_connections = conn2.num_connections + 1

      --log:debug('connecting entities')
      self:_update_entity_changes_connector(e1.entity, conn1.type, c1.name, c2.id, connected_graph_id, potential_connection.this_rank)
      self:_update_entity_changes_connector(e2.entity, conn1.type, c2.name, c1.id, connected_graph_id, potential_connection.target_rank)
   end

   for dc1, dc2 in pairs(connectors_disconnected) do
      -- if we disconnected some connectors, make sure the entities that were connected to them seek new connections
      -- (as long as they aren't either of these entities)
      -- dc1 is either c1 or c2; dc2 is the worst connector we disconnected from it ({id, rank})
      if dc2.entity_id ~= e1.id and dc2.entity_id ~= e2.id then
         local _, added_graphs_changed = self:_add_entity_to_graphs(self._entities[dc2.entity_id], conn1.type)
         added_graphs_changed = added_graphs_changed[conn1.type]
         if added_graphs_changed and next(added_graphs_changed) then
            combine_tables(graphs_changed, added_graphs_changed)
         end
      end
   end

   return graphs_changed
end

function PlayerConnections:_get_worst_connection(connector)
   local worst_id
   local worst_rank

   for id, rank in pairs(connector.connected_to) do
      if not worst_rank or rank < worst_rank then
         worst_id = id
         worst_rank = rank
      end
   end

   return worst_id, worst_rank
end

function PlayerConnections:_try_disconnecting_connectors(c1, c2, removing_entity)
   if c1 == c2 then
      --log:debug('can\'t disconnect a %s from %s (equal)', c1.id, c2.id)
      return nil
   end

   if not c1.connected_to[c2.id] or not c2.connected_to[c1.id] then
      --log:debug('can\'t disconnect a %s from %s (not connected)', c1.id, c2.id)
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
      --log:debug('can\'t disconnect a %s from %s (different type or same entity)', c1.id, c2.id)
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
   -- process through the 'connected_nodes' of e1 and see if it reaches e2
   -- if not, remove e1 and all connections it has to a new graph

   local conn_tbl = self:get_connections(conn1.type)
   local graphs_changed = {}

   self:_update_entity_changes_connector(e1.entity, conn1.type, c1.name, c2.id)
   self:_update_entity_changes_connector(e2.entity, conn1.type, c2.name, c1.id)

   if conn_tbl.maintain_graphs then
      local graph_indexes = conn_tbl.graphs
      local graphs = self:_get_graphs(graph_indexes)

      for id, graph in pairs(graphs) do
         local n1 = graph.nodes[e1.id]
         local n2 = graph.nodes[e2.id]

         if n1 and n1.connected_nodes[e2.id] then
            n1.connected_nodes[e2.id] = nil
            --log:debug('disconnecting connector')
            if not next(n1.connected_nodes) then
               graph.nodes[e1.id] = nil
               graphs_changed[graph.id] = true
               n1 = nil
            end
         end

         if n2 and n2.connected_nodes[e1.id] then
            n2.connected_nodes[e1.id] = nil
            --log:debug('disconnecting connector')
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

         if n1 and n2 and not removing_entity then
            -- they both have other connections; check recursively to see if they're still connected to one another
            local split_changes = self:_split_graph_deep_disconnected(graph_indexes, graph, {[e1.id] = true, [e2.id] = true})
            
            if split_changes then
               combine_tables(graphs_changed, split_changes)
            end
         end

         if next(graphs_changed) then
            return graphs_changed
         end
      end
   end

   return graphs_changed
end

function PlayerConnections:_split_graph_deep_disconnected(graph_indexes, graph, node_ids)
   -- we want to do a breadth-first search; almost always, if nodes are connected to one another, we'll find that faster with breadth-first than depth-first
   -- we want to cancel the search as soon as it finds the node(s) instead of traversing everything
   -- create new graphs when necessary
   log:debug('_split_graph_deep_disconnected %s, %s', graph.id, radiant.util.table_tostring(node_ids))

   local graphs_changed = {}

   local node_id_seq = radiant.keys(node_ids)
   local total_count = #node_id_seq
   if total_count > 1 then
      local count = total_count
      for i = 1, total_count do
         local node_id = node_id_seq[i]
         -- if we still have to check this node; it wasn't removed by being found connected to a previous node
         if node_ids[node_id] then
            local to_check = {node_id}
            local checked = {}
            local has_nodes = false
            local to_check_index = 0

            while to_check_index < #to_check do
               -- we add to the end, remove from the start
               to_check_index = to_check_index + 1
               local start_node_id = to_check[to_check_index]
               if node_ids[start_node_id] then
                  node_ids[start_node_id] = nil
                  count = count - 1
                  if count < 1 then
                     -- we found all the nodes!
                     return graphs_changed
                  end
               end

               local n = graph.nodes[start_node_id]
               checked[start_node_id] = n or false
               -- if the node doesn't exist, it was already severed from the graph and we don't need to worry about it
               if n and next(n.connected_nodes) then
                  has_nodes = true
                  
                  for n_id, _ in pairs(n.connected_nodes) do
                     if checked[n_id] == nil then
                        table.insert(to_check, n_id)
                     end
                  end
               end
            end

            -- we parsed through all the connected nodes of the start node and didn't find all the things we're looking for
            -- we may have found some of them, but not all, so make a new graph with these nodes
            if has_nodes then
               local new_graph = stonehearth_ace.connection:_create_new_graph(graph.type, self._sv.player_id)
               graph_indexes[new_graph.id] = true
               for id, node in pairs(checked) do
                  graph.nodes[id] = nil
                  if node then
                     new_graph.nodes[id] = node
                     local e = self._entities[id]
                     if e then
                        --log:debug('changing graph')
                        self:_update_entity_changes_connector(e.entity, graph.type, nil, nil, new_graph.id)
                     end
                  end
               end
               graphs_changed[graph.id] = true
               graphs_changed[new_graph.id] = true
            end
         end
      end
   end

   return graphs_changed
end

function PlayerConnections:_find_best_potential_connections(connection, entity_id_to_ignore)
   local result = {}
   if connection.num_connections < connection.max_connections then
      for _, connector_id in pairs(connection.connectors) do
         local connector = self._connectors[connector_id]
         if connector.max_connections > 0 and connector.region_area > 0 then
            local potential_connectors = self:_find_best_potential_connectors(connector, entity_id_to_ignore)
            for _, conn in ipairs(potential_connectors) do
               table.insert(result, conn)
            end
         end
      end
   end

   table.sort(result, function(a, b) return a.this_rank > b.this_rank end)
   return result
end

function PlayerConnections:_find_best_potential_connectors(connector, entity_id_to_ignore)
   local result = {}
   local ids_to_ignore = {}
   ids_to_ignore[connector.entity_id] = true
   if entity_id_to_ignore then
      ids_to_ignore[entity_id_to_ignore] = true
   end
   
   if connector.trans_region then
      local r = connector.trans_region
      local conn_locs = self:get_connections(connector.connection).connector_locations
      
      -- we only need to check other connectors that are in region chunks that this one intersects
      for _, crk in ipairs(connector.chunk_region_keys) do
         --log:debug('testing crk %s', crk)
         for id, _ in pairs(conn_locs[crk]) do
            local conn = self._connectors[id]
            --log:debug('seeing if %s can connect to %s', connector.id, id)
            --log:debug('conn %s: %s, %s', id, conn.connection.entity_struct.id, connection.entity_struct.id)
            if not ids_to_ignore[conn.entity_id]
                  and conn.max_connections > 0
                  and conn.trans_region
                  and conn.region_area > 0 then
               
               local intersects = r:intersects_region(conn.trans_region)
               if intersects then
                  local intersection = r:intersect_region(conn.trans_region):get_area()
                  --log:debug('checking intersection of connection regions %s and %s', connector.trans_region:get_bounds(), conn.trans_region:get_bounds())
                  if intersection > 0 then
                     -- rank potential connectors by how closely their regions intersect
                     local rank_connector = intersection / connector.region_area
                     local rank_conn = intersection / conn.region_area
                     --log:debug('they intersect! %s and %s', rank_connector, rank_conn)
                     -- the rank has to meet the threshold for each connector
                     if rank_connector >= connector.region_intersection_threshold and rank_conn >= conn.region_intersection_threshold then
                        table.insert(result, {
                           connector = connector,
                           target_connector = conn,
                           this_rank = rank_connector,
                           target_rank = rank_conn
                        })
                     end
                  end
               end
            end
         end
      end
   end

   return result
end

function PlayerConnections:_update_connector_locations(entity_struct, new_location, new_rotation, only_type, only_connector)
   -- when the location is nil, request it; if it's false, it's because the entity is being removed
   if new_location == nil then
      new_location = radiant.entities.get_world_grid_location(entity_struct.entity)
   end
   -- this is done in two steps so that if rotation is specified as false, we don't need to call get_facing
   if new_rotation == nil then
      new_rotation = radiant.entities.get_facing(entity_struct.entity)
   end
   new_rotation = (new_rotation and (new_rotation + 360) % 360) or 0

   -- rotate according to the entity's facing direction, then translate to the new location

   for conn_type, connection in pairs(entity_struct.connections) do
      if not only_type or conn_type == only_type then
         local conn_locs = self:get_connections(conn_type).connector_locations
         
         for _, connector_id in pairs(connection.connectors) do
            if not only_connector or only_connector == connector_id then
               local connector = self._connectors[connector_id]
               --log:debug('rotating region %s by %s°, then translating by %s', connector.region, new_rotation, new_location or '[NIL]')
               if new_location and connector.region then
                  connector.trans_region = radiant.entities.local_to_world(connector.region, entity_struct.entity)   --:translated(connection.origin_offset)
                  -- connector.trans_region = rotate_region(connector.region, connection.origin_offset, new_rotation, entity_struct.align_x, entity_struct.align_z)
                  --       :translated(new_location)
                  --log:debug('connector %s trans_region bounds: %s', connector_id, connector.trans_region:get_bounds())
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
   end
end

-- get all the region group keys that a particular cube intersects
function PlayerConnections:_get_region_keys(region)
   local keys = {}
   if region then
      local bounds = region:get_bounds()
      local min = bounds.min
      local max = bounds.max
      local chunk_region_size = _chunk_region_size
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