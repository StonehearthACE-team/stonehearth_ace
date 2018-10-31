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

local combine_tables = ConnectionUtils.combine_tables
local combine_type_tables = ConnectionUtils.combine_type_tables
local combine_entity_tables = ConnectionUtils.combine_entity_tables
local _update_entity_connection_data = ConnectionUtils._update_entity_connection_data

function ConnectionService:initialize()
   local json = radiant.resources.load_json('stonehearth_ace:data:connection_types')
   self._registered_types = (json and json.types) or {}
   for type, type_details in pairs(self._registered_types) do
      type_details.separated_by_player = type_details.separated_by_player or false
   end
   self._traces = {}
   
   self._sv = self.__saved_variables:get_data()
   local sv_needs_fix = not self._sv.connections or not self._sv.graphs or not self._sv.new_graph_id or not self._sv.connections_ds
   if sv_needs_fix then
      -- First time around or something was improperly configured before.
      self._sv.connections = self._sv.connections or {}
      self._sv.graphs = self._sv.graphs or {}
      self._sv.new_graph_id = self._sv.new_graph_id or 1
      self._sv.connections_ds = self._sv.connections_ds or {}

      for k, v in pairs(self._sv.connections) do
         self:_destroy_player_connections(k)
      end

      for k, v in pairs(self._sv.graphs) do
         self:_remove_graph(k)
      end

      for k, v in pairs(self._sv.connections_ds) do
         v:destroy()
         self._sv.connections_ds[k] = nil
      end
   else
      -- Reloading. Copy existing data into the cache.
      for k, v in pairs(self._sv.connections) do
         CONNECTIONS_BY_PLAYER_ID[k] = v
      end
      for k, v in pairs(self._sv.graphs) do
         local graphs = self:get_graphs_by_type(v.type)
         graphs[k] = v
      end
   end
end

function ConnectionService:activate()
   
end

function ConnectionService:destroy()

end

function ConnectionService:_stop_all_traces()
   for id, traces in pairs(self._traces) do
      self:_stop_entity_traces(id)
   end
end

function ConnectionService:get_graphs_by_type(type)
   local graphs = GRAPHS_BY_TYPE[type]
   if not graphs then
      graphs = {}
      GRAPHS_BY_TYPE[type] = graphs
   end
   return graphs
end

function ConnectionService:is_separated_by_player(type)
   local type_details = self._registered_types[type]
   return type_details and type_details.separated_by_player
end

function ConnectionService:register_entity(entity, connections)
   -- register this entity with the proper player's connections
   local player_id = entity:get_player_id()
   local player_connections = self:get_player_connections(player_id)
   local all_players_connections = self:get_player_connections(ALL_PLAYERS)
   local res1 = player_connections:register_entity(entity, connections, true)  -- separated by player
   local res2 = all_players_connections:register_entity(entity, connections, false)

   self:_perform_update(player_id, res1, res2)
   
   self:_start_entity_traces(entity, player_connections, all_players_connections)
end

function ConnectionService:unregister_entity(entity)
   local player_id = entity:get_player_id()
   local res1 = self:get_player_connections(player_id):unregister_entity(entity)
   local res2 = self:get_player_connections(ALL_PLAYERS):unregister_entity(entity)

   self:_perform_update(player_id, res1, res2)
   
   self:_stop_entity_traces(entity:get_id())
end

function ConnectionService:get_connection_types_command(session, response)
   return {types = self._registered_types}
end

function ConnectionService:get_connections_datastore_command(session, response)
   return { connections = self:get_connections_datastore(session.player_id) }
end

function ConnectionService:get_connections_datastore(player_id)
   local ds = self._sv.connections_ds[player_id]
   if not ds then
      ds = radiant.create_datastore()
      self._sv.connections_ds[player_id] = ds
      ds:set_data({})
      self.__saved_variables:mark_changed()
   end
   return ds
end

function ConnectionService:get_disconnected_entities(player_id, type)
   return get_player_connections(player_id or ALL_PLAYERS):get_disconnected_entities(type)
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

function ConnectionService:_destroy_player_connections(player_id)
   local connections = self._sv.connections[player_id]
   if connections then
      connections:destroy()
      self._sv.connections[player_id] = nil
      CONNECTIONS_BY_PLAYER_ID[player_id] = nil
   end
end

function ConnectionService:_create_new_graph(type)
   local id = self._sv.new_graph_id
   local graphs = self._sv.graphs
   while graphs[id] do
      id = id + 1
   end
   self._sv.new_graph_id = id
   local graph = {id = id, type = type, nodes = {}}
   graphs[id] = graph
   self:get_graphs_by_type(type)[id] = graph
   self.__saved_variables:mark_changed()

   return graph
end

function ConnectionService:_remove_graph(id)
   local graph = self._sv.graphs[id]
   if graph then
      self:get_graphs_by_type(graph.type)[id] = nil
      self._sv.graphs[id] = nil
      self.__saved_variables:mark_changed()
   end
end

function ConnectionService:_perform_update(player_id, res1, res2)
   combine_tables(res1.changed_types, res2.changed_types)
   res1.graphs_changed = combine_type_tables(res1.graphs_changed, res2.graphs_changed)
   res1.entity_changes = combine_entity_tables(res1.entity_changes, res2.entity_changes)
   self:_communicate_update(player_id, res1)
end

function ConnectionService:_communicate_update(player_id, args)
   local ds = self:get_connections_datastore(player_id)
   local cur_data = ds:get_data()
   
   for entity, stats in pairs(args.entity_changes) do
      entity:get_component('stonehearth_ace:connection'):set_connected_stats(stats)
      
      local entity_data = cur_data[entity:get_id()]
      if not entity_data then
         entity_data = {}
         cur_data[entity:get_id()] = entity_data
      end
      _update_entity_connection_data(entity_data, stats)
   end

   ds:set_data(cur_data)

   for type, _ in pairs(args.changed_types) do
      radiant.events.trigger(self, 'stonehearth_ace:connections:'..type..':changed', type, args.graphs_changed[type] or {})
   end
end

function ConnectionService:_start_entity_traces(entity, player_connections, all_players_connections)
   local id = entity:get_id()
   local player_id = entity:get_player_id()

   if not self._traces[id] then
      local traces = {}
      traces._parent_trace = entity:add_component('mob'):trace_parent('connection entity added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world
               local res1 = player_connections:remove_entity(id)
               local res2 = all_players_connections:remove_entity(id)
               self:_perform_update(player_id, res1, res2)
            else
               --we were just added to the world
               -- this will get handled by the (location) trace_transform
            end
         end)

      traces._location_trace = entity:add_component('mob'):trace_transform('connection entity moved', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
            local res1 = player_connections:update_entity(id)
            local res2 = all_players_connections:update_entity(id)
            self:_perform_update(player_id, res1, res2)
         end)

      traces._player_trace = entity:trace_player_id('connection service')
      :on_changed(function(new_player_id)
            if new_player_id ~= player_id then
               local result = player_connections:unregister_entity(entity)
               if result then
                  self:_communicate_update(player_id, result)
               end

               local connections = entity:get_component('stonehearth_ace:connection'):get_connections()
               result = self:get_player_connections(new_player_id):register_entity(entity, connections, true)  -- separated by player
               self:_communicate_update(new_player_id, result)
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

return ConnectionService