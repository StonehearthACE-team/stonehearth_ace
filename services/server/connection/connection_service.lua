--[[
   the service mostly just manages the controllers for player connections (similar to the inventory service)
   and allows entities to easily be registered or unregistered
   since this service separates entities by player, entities owned by different players will not "connect" to one another
]]

local PlayerConnections = require 'services.server.connection.player_connections'
local ConnectionUtils = require 'lib.connection.connection_utils'

local log = radiant.log.create_logger('connection')

local ConnectionService = class()

-- using a local cache for these just like the inventory uses
-- mods that make use of this might make frequent calls here, and it's very little overhead
local CONNECTIONS_BY_PLAYER_ID = {}
local GRAPHS_BY_TYPE = {}
local ALL_PLAYERS = '_all_players_'
local IS_SHUTTING_DOWN = false

local combine_tables = ConnectionUtils.combine_tables
local combine_type_tables = ConnectionUtils.combine_type_tables
local _update_entity_connection_data = ConnectionUtils._update_entity_connection_data
local _update_connection_data = ConnectionUtils._update_connection_data

function ConnectionService:initialize()
   local json = radiant.resources.load_json('stonehearth_ace:data:connection_types')
   self._registered_types = (json and json.types) or {}
   for conn_type, type_details in pairs(self._registered_types) do
      type_details.separated_by_player = type_details.separated_by_player or false
   end
   self._traces = {}
   
   self._sv = self.__saved_variables:get_data()
   self._sv.connections_ds = nil
   self._sv.graphs = nil
   self._graphs = {}

   local sv_needs_fix = not self._sv.connections or not self._sv.new_graph_id
   if sv_needs_fix then
      -- First time around or something was improperly configured before.
      self._sv.connections = self._sv.connections or {}
      self._sv.new_graph_id = self._sv.new_graph_id or 1

      for k, v in pairs(self._sv.connections) do
         self:_destroy_player_connections(k)
      end
   else
      -- Reloading. Copy existing data into the cache.
      for k, v in pairs(self._sv.connections) do
         CONNECTIONS_BY_PLAYER_ID[k] = v
      end
   end

   self._game_shut_down_listener = radiant.events.listen_once(radiant, 'radiant:shut_down', function()
      self._game_shut_down_listener = nil
      IS_SHUTTING_DOWN = true
      log:debug('connection service shutting down')
   end)
end

function ConnectionService:destroy()
   if self._game_shut_down_listener then
      self._game_shut_down_listener:destroy()
      self._game_shut_down_listener = nil
   end

   self:_stop_all_traces()
end

function ConnectionService:_stop_all_traces()
   for id, traces in pairs(self._traces) do
      self:_stop_entity_traces(id)
   end
end

function ConnectionService:get_graphs_by_type(conn_type)
   local graphs = GRAPHS_BY_TYPE[conn_type]
   if not graphs then
      graphs = {}
      GRAPHS_BY_TYPE[conn_type] = graphs
   end
   return graphs
end

function ConnectionService:get_graph_by_id(id, player_id, conn_type)
   local graph = self._graphs[id]
   if not graph and player_id and conn_type then
      graph = self:_create_new_graph(conn_type, player_id, id)
   end
   return graph
end

function ConnectionService:is_separated_by_player(conn_type)
   local type_details = self._registered_types[conn_type]
   return type_details and type_details.separated_by_player
end

function ConnectionService:should_maintain_graphs(conn_type)
   local type_details = self._registered_types[conn_type]
   return type_details and type_details.maintain_graphs
end

function ConnectionService:register_entity(entity, connections, connected_stats)
   -- register this entity with the proper player's connections
   local player_id = entity:get_player_id()
   local player_connections = self:get_player_connections(player_id)
   local all_players_connections = self:get_player_connections(ALL_PLAYERS)
   local res1 = player_connections:register_entity(entity, connections, true, connected_stats)  -- separated by player
   local res2 = all_players_connections:register_entity(entity, connections, false, connected_stats)

   self:_perform_update(player_id, res1, res2)
   
   self:_start_entity_traces(entity, player_connections, all_players_connections)
end

function ConnectionService:unregister_entity(entity)
   --log:debug('unregistering connection entity %s', entity)
   if not IS_SHUTTING_DOWN then
      local player_id = entity:get_player_id()
      local res1 = self:get_player_connections(player_id):unregister_entity(entity)
      local res2 = self:get_player_connections(ALL_PLAYERS):unregister_entity(entity)

      self:_perform_update(player_id, res1, res2)
   end
   
   self:_stop_entity_traces(entity:get_id())
end

function ConnectionService:update_connector(entity, conn_type, connection_max_connections, name, connector)
   local result
   local player_id = entity:get_player_id()
   local player_connections = self:get_player_connections(player_id)
   local all_players_connections = self:get_player_connections(ALL_PLAYERS)

   if self:is_separated_by_player(conn_type) then
      result = player_connections:update_connector(entity, conn_type, connection_max_connections, name, connector)
   else
      result = all_players_connections:update_connector(entity, conn_type, connection_max_connections, name, connector)
   end

   self:_perform_update(player_id, result)
   self:_start_entity_traces(entity, player_connections, all_players_connections)
end

function ConnectionService:remove_connector(entity, conn_type, name)
   local result
   local player_id = entity:get_player_id()
   local player_connections = self:get_player_connections(player_id)
   local all_players_connections = self:get_player_connections(ALL_PLAYERS)

   if self:is_separated_by_player(conn_type) then
      result = player_connections:remove_connector(entity, conn_type, name)
   else
      result = all_players_connections:remove_connector(entity, conn_type, name)
   end

   self:_perform_update(player_id, result)
   self:_start_entity_traces(entity, player_connections, all_players_connections)
end

function ConnectionService:get_connection_types_command(session, response)
   return {types = self._registered_types}
end

function ConnectionService:get_connections_data_command(session, response, types)
   return { connections = self:get_connections_data(session.player_id, types) }
end

function ConnectionService:get_connections_data(player_id, types)
   local data = {}

   if types and next(types) then
      for _, conn_type in ipairs(types) do
         if self._registered_types[conn_type].separated_by_player then
            _update_connection_data(data, self:get_player_connections(player_id):get_connections_data(conn_type))
         else
            _update_connection_data(data, self:get_player_connections(ALL_PLAYERS):get_connections_data(conn_type))
         end
      end
   else
      _update_connection_data(data, self:get_player_connections(player_id):get_connections_data())
      _update_connection_data(data, self:get_player_connections(ALL_PLAYERS):get_connections_data())
   end

   return data
end

function ConnectionService:get_entities_in_selected_graphs_command(session, response, selected_id)
   local entities = {}
   if selected_id then
      for _, graph in pairs(self._graphs) do
         if graph.nodes[selected_id] then
            for id, _ in pairs(graph.nodes) do
               entities[id] = true
            end
         end
      end
   end
   response:resolve({entities = entities})
end

function ConnectionService:get_disconnected_entities(player_id, conn_type)
   return self:get_player_connections(player_id or ALL_PLAYERS):get_disconnected_entities(conn_type)
end

function ConnectionService:get_player_connections(player_id)
   local connections = rawget(CONNECTIONS_BY_PLAYER_ID, player_id)
   
   if not connections then
      connections = radiant.create_controller('stonehearth_ace:player_connections', player_id)
      CONNECTIONS_BY_PLAYER_ID[player_id] = connections
      self._sv.connections[player_id] = connections
      self.__saved_variables:mark_changed()
      radiant.events.trigger(self, 'stonehearth:ace:connections:player_connections_created', player_id)
   end

   return connections
end

function ConnectionService:get_entity_from_connector(connector_id)
   for _, connections in pairs(self._sv.connections) do
      local entity = connections:get_entity_from_connector(connector_id)
      if entity then
         return entity
      end
   end
end

function ConnectionService:_destroy_player_connections(player_id)
   local connections = self._sv.connections[player_id]
   if connections then
      connections:destroy()
      self._sv.connections[player_id] = nil
      CONNECTIONS_BY_PLAYER_ID[player_id] = nil
      self.__saved_variables:mark_changed()
   end
end

function ConnectionService:_create_new_graph(conn_type, player_id, id)
   local graphs = self._graphs
   if not id then
      id = self._sv.new_graph_id
      while graphs[id] do
         id = id + 1
      end
      self._sv.new_graph_id = id
      self.__saved_variables:mark_changed()
   end
   local graph = {id = id, type = conn_type, player_id = player_id, nodes = {}}
   graphs[id] = graph
   self:get_graphs_by_type(conn_type)[id] = graph

   return graph
end

function ConnectionService:_remove_graph(id)
   local graph = self._graphs[id]
   if graph then
      self:get_graphs_by_type(graph.type)[id] = nil
      self._graphs[id] = nil
   end
end

function ConnectionService:_perform_update(player_id, res1, res2)
   if not res1 or not res2 then
      res1 = res1 or res2
   end
   if res1 then
      --log:debug('_perform_update res1: %s\n_perform_update res2: %s', radiant.util.table_tostring(res1.entity_changes), res2 and radiant.util.table_tostring(res2.entity_changes))
      if res2 then
         combine_tables(res1.changed_types, res2.changed_types)
         res1.graphs_changed = combine_type_tables(res1.graphs_changed, res2.graphs_changed)
      end
      self:_communicate_update(player_id, res1)
   end
end

function ConnectionService:_communicate_update(player_id, args)
   for conn_type, _ in pairs(args.changed_types) do
      radiant.events.trigger(self, 'stonehearth_ace:connections:'..conn_type..':changed', conn_type, args.graphs_changed[conn_type] or {})
   end
end

function ConnectionService:_start_entity_traces(entity, player_connections, all_players_connections)
   local id = entity:get_id()
   local player_id = entity:get_player_id()

   if not self._traces[id] then
      local traces = {}
      traces._parent_trace = entity:add_component('mob'):trace_parent('connection entity added or removed')
      :on_changed(function(parent_entity)
         if not parent_entity then
            --we were just removed from the world
            log:debug('%s removed from world', id)
            local res1 = player_connections:remove_entity(id)
            local res2 = all_players_connections:remove_entity(id)
            self:_perform_update(player_id, res1, res2)
         else
            --we were just added to the world
            -- this *should* get handled by the (location) trace_transform but perhaps doesn't?
            --log:debug('entity %s added to world', entity)
            local res1 = player_connections:update_entity(id, true)
            local res2 = all_players_connections:update_entity(id, true)
            self:_perform_update(player_id, res1, res2)
         end
      end)

      traces._location_trace = entity:add_component('mob'):trace_transform('connection entity moved')
      :on_changed(function()
         log:debug('entity %s moved or rotated', entity)
         local res1 = player_connections:update_entity(id)
         local res2 = all_players_connections:update_entity(id)
         self:_perform_update(player_id, res1, res2)
      end)

      traces._player_trace = entity:trace_player_id('connection service')
      :on_changed(function(new_player_id)
         if new_player_id ~= player_id then
            log:debug('entity %s player_id changed from %s to %s', entity, player_id, new_player_id)
            local result = player_connections:unregister_entity(entity)
            if result then
               self:_communicate_update(player_id, result)
            end

            local connections = entity:get_component('stonehearth_ace:connection'):get_connections()
            result = self:get_player_connections(new_player_id):register_entity(entity, connections, true)  -- separated by player
            self:_communicate_update(new_player_id, result)
            player_id = new_player_id
         end
      end)
      
      self._traces[id] = traces
   end
end

function ConnectionService:_stop_entity_traces(id)
   local traces = self._traces[id]

   if traces then
      if traces._parent_trace then
         traces._parent_trace:destroy()
         traces._parent_trace = nil
      end
      if traces._location_trace then
         traces._location_trace:destroy()
         traces._location_trace = nil
      end
      if traces._player_trace then
         traces._player_trace:destroy()
         traces._player_trace = nil
      end

      self._traces[id] = nil
   end
end

--[[
function ConnectionService:saved_variables_mark_changed()
   for _, controller in pairs(self._sv.connections) do
      controller.__saved_variables:mark_changed()
   end
   self.__saved_variables:mark_changed()
end
]]

return ConnectionService