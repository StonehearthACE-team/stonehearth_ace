--[[
   vines need to be able to grow when they're alone as well as when they're connected in graphs
]]
local log = radiant.log.create_logger('vine_controller')
local rng = _radiant.math.get_default_rng()

local VineController = class()

local FAILED_GROWTH_DELAY = '10m'
local MIN_GROWTH_PERIOD

function VineController:initialize()
   
end

function VineController:create(uri, type_data)
   self._sv.uri = uri
   self._sv.type_data = type_data
   self._sv.graph_growth_timers = {}
end

function VineController:activate()
   MIN_GROWTH_PERIOD = stonehearth.calendar:debug_game_seconds_to_realtime(1, true)
   
   self._game_loaded_listener = radiant.events.listen_once(radiant, 'radiant:game_loaded', function()
      self._game_loaded_listener = nil
      self:_update_graphs()
   end)

   self._connections_changed_listener = radiant.events.listen(stonehearth_ace.connection,
         'stonehearth_ace:connections:'..self._sv.uri..':changed', self, self._on_connections_changed)

   self._networks_by_entity = {}
   self._graphs = {}
   self._changed_graphs = {}
   self:_update_disconnected_growth_timer()
end

function VineController:destroy()
	self:_destroy_listeners()
end

function VineController:_destroy_listeners()
   if self._connections_changed_listener then
      self._connections_changed_listener:destroy()
      self._connections_changed_listener = nil
   end
   for id, timer in pairs(self._sv.graph_growth_timers) do
      timer:destroy()
      self._sv.graph_growth_timers[id] = nil
   end
   if self._sv.disconnected_growth_timer then
      self._sv.disconnected_growth_timer:destroy()
      self._sv.disconnected_growth_timer = nil
   end
end

function VineController:_update_graphs()
   local graphs = stonehearth_ace.connection:get_graphs_by_type(self._sv.uri)
   for id, graph in pairs(graphs) do
      self:_update_graph(id, graph)
   end
end

function VineController:_on_connections_changed(type, graphs_changed)
   for id, _ in pairs(graphs_changed) do
      if self._graphs[id] then
         self._changed_graphs[id] = true
      else
         self:_force_update_graph(id)
      end
   end
end

function VineController:_force_update_graph(id)
   self:_update_graph(id, stonehearth_ace.connection:get_graph_by_id(id))
end

function VineController:_update_graph(id, graph)
   if graph then
      self:_update_graph_contents(id, graph)
      self:_update_graph_growth_timer(id)
   else
      if self._sv.graph_growth_timers[id] then
         self._sv.graph_growth_timers[id]:destroy()
         self._sv.graph_growth_timers[id] = nil
         self.__saved_variables:mark_changed()
      end
      self._graphs[id] = nil
   end
end

function VineController:_update_graph_contents(id, graph)
   local g = {}
   self._graphs[id] = g
   for e_id, _ in pairs(graph.nodes) do
      table.insert(g, e_id)
   end
end

function VineController:_update_graph_growth_timer(id, expired)
   -- this function gets called if we're creating/updating/recreating growth timers
   -- don't actually update existing timers; only create new ones or recreate expired ones
   if self._sv.graph_growth_timers[id] and not expired then
      return
   end

   local graph = self._graphs[id]
   -- if the graph table no longer exists, it's because this graph was merged or destroyed since the timer was set
   if not graph then
      return
   end

   if self._changed_graphs[id] then
      self._changed_graphs[id] = nil
      self:_force_update_graph(id)
      graph = self._graphs[id]
      if not graph then
         return
      end
   end

   local count = #graph

   -- update timer duration based on number of entities
   local period = self:_get_growth_period(count)
   
   if expired then
      if self._sv.graph_growth_timers[id] then
         self._sv.graph_growth_timers[id]:destroy()
         self._sv.graph_growth_timers[id] = nil
      end
      
      -- try to grow at most as many times as there are entities in the graph
      local grew = false
      for i = 1, count do
         local index = rng:get_int(1, count)
         local entity = radiant.entities.get_entity(graph[i])
         if entity then
            local comp = entity:get_component('stonehearth_ace:vine')
            if comp and comp:try_grow() then
               grew = true
               break
            end
         end
      end
      -- don't try to grow for a while if we fail to grow
      if not grew and period and period > 0 then
         period = period + stonehearth.calendar:parse_duration(FAILED_GROWTH_DELAY)
      end
   end

   if period and period > 0 and not self._sv.graph_growth_timers[id] then
      self._sv.graph_growth_timers[id] = stonehearth.calendar:set_persistent_timer("vine grow_callback",
            period, radiant.bind(self, '_update_graph_growth_timer', id, true))
   end

   if expired then
      self.__saved_variables:mark_changed()
   end
end

function VineController:_get_growth_period(count, divisor)
   divisor = math.sqrt(math.max(1, divisor or count))
   local time = ''
   for _, growth_time in pairs(self._sv.type_data.growth_times) do
      if count >= growth_time.threshold then
         time = growth_time.time
      else
         break
      end
   end
   time = stonehearth.calendar:parse_duration(time)
   if time > 0 then
      time = math.max(MIN_GROWTH_PERIOD, stonehearth.town:calculate_growth_period('', time / divisor))
   end
   return time
end

function VineController:_update_disconnected_growth_timer(expired)
   local dc_count = 0
   if expired then
      local entities = stonehearth_ace.connection:get_disconnected_entities(nil, self._sv.uri)
      dc_count = #entities
      if dc_count > 0 then
         local index = rng:get_int(1, dc_count)
         local entity = radiant.entities.get_entity(entities[index])
         if entity then
            local comp = entity:get_component('stonehearth_ace:vine')
            if comp then
               comp:try_grow()
            end
         end
      end

      if self._sv.disconnected_growth_timer then
         self._sv.disconnected_growth_timer:destroy()
         self._sv.disconnected_growth_timer = nil
      end
   end
   
   if not self._sv.disconnected_growth_timer then
      local period = self:_get_growth_period(1, dc_count)
      if period > 0 then
         self._sv.disconnected_growth_timer = stonehearth.calendar:set_persistent_timer("disconnected vine grow_callback",
               period, radiant.bind(self, '_update_disconnected_growth_timer', true))
      end
   end

   self.__saved_variables:mark_changed()
end

return VineController
