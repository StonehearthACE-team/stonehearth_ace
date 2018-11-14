--[[
   vines need to be able to grow when they're alone as well as when they're connected in graphs
]]
local log = radiant.log.create_logger('vine_service')
local rng = _radiant.math.get_default_rng()

local VineService = class()

local FAILED_GROWTH_DELAY = '10m'

function VineService:initialize()
   self._networks_by_entity = {}
   local json = radiant.resources.load_json('stonehearth_ace:data:vine_types')
   self._vine_types = json.types or {}

   self._sv = self.__saved_variables:get_data()

   if not self._sv.graph_tbls then
      self._sv.graph_tbls = {}
      self:_update_graphs()
   end
   if not self._sv.disconnected_growth_timers then
      self._sv.disconnected_growth_timers = {}
   end

   -- query connection service for connection info and listen for changes
   for type, _ in pairs(self._vine_types) do
      self._connections_changed_listener = radiant.events.listen(stonehearth_ace.connection,
            'stonehearth_ace:connections:'..type..':changed', self, self._on_connections_changed)
   end

   self:_update_disconnected_growth_timers()
end

function VineService:destroy()
	self:_destroy_listeners()
end

function VineService:_destroy_listeners()
   if self._connections_changed_listener then
      self._connections_changed_listener:destroy()
      self._connections_changed_listener = nil
   end
   for id, _ in pairs(self._entity_listeners) do
      self:_destroy_entity_listener(id)
   end
end

function VineService:get_growth_data(uri)
   return self._vine_types[uri]
end

function VineService:_update_graphs()
   for type, _ in pairs(self._vine_types) do
      local graphs = stonehearth_ace.connection:get_graphs_by_type(type)
      for id, graph in pairs(graphs) do
         self:_update_graph(id, graph)
      end
   end
end

function VineService:_on_connections_changed(type, graphs_changed)
   for id, _ in pairs(graphs_changed) do
      self:_update_graph(id, stonehearth_ace.connection:get_graph_by_id(id))
   end
   self.__saved_variables:mark_changed()
end

function VineService:_update_graph(id, graph)
   local g = self._sv.graph_tbls[id]
   if graph then
      if not g then
         g = {type = graph.type}
         self._sv.graph_tbls[id] = g   
      end
      g.graph = {}
      for e_id, e in pairs(graph.nodes) do
         table.insert(g.graph, e.entity_struct.entity)
      end

      self:_update_graph_growth_timer(id)
   else
      if g and g.growth_timer then
         g.growth_timer:destroy()
      end
      self._sv.graph_tbls[id] = nil
   end
end

function VineService:_update_graph_growth_timer(id, expired)
   -- this function gets called if we're creating/updating/recreating growth timers
   local graph_tbl = self._sv.graph_tbls[id]
   -- if the graph table no longer exists, it's because this graph was merged or destroyed since the timer was set
   if not graph_tbl then
      return
   end

   local count = #graph_tbl.graph

   -- update timer duration based on number of entities
   local period
   if expired then
      period = graph_tbl.period
   else
      period = self:_get_growth_period(graph_tbl.type, count)
      graph_tbl.period = period
   end
   
   if expired then
      if graph_tbl.growth_timer then
         graph_tbl.growth_timer:destroy()
         graph_tbl.growth_timer = nil
      end
      
      -- try to grow at most as many times as there are entities in the graph
      local grew = false
      for i = 1, count do
         local index = rng:get_int(1, count)
         local comp = graph_tbl.graph[i]:get_component('stonehearth_ace:vine')
         if comp and comp:try_grow() then
            grew = true
            break
         end
      end
      -- don't try to grow for a while if we fail to grow
      if not grew then
         period = period + stonehearth.calendar:parse_duration(FAILED_GROWTH_DELAY)
      end
   end

   if period and period > 0 and not graph_tbl.growth_timer then
      graph_tbl.growth_timer = stonehearth.calendar:set_persistent_timer("vine grow_callback",
            period, function()
               self:_update_graph_growth_timer(id, true)
            end)
   end

   if expired then
      self.__saved_variables:mark_changed()
   end
end

function VineService:_get_growth_period(type, count)
   local time = ''
   for _, growth_time in pairs(self._vine_types[type].growth_times) do
      if count >= growth_time.threshold then
         time = growth_time.time
      else
         break
      end
   end
   time = stonehearth.calendar:parse_duration(time)
   if time > 0 then
      time = stonehearth.town:calculate_growth_period('', time / math.max(1, count))
   end
   return time
end

function VineService:_update_disconnected_growth_timers()
   -- try to grow one of each type
   for type, _ in pairs(self._vine_types) do
      self:_update_disconnected_growth_timer(type)
   end
end

function VineService:_update_disconnected_growth_timer(type, expired)
   local dc_count = 0
   if expired then
      local entities = stonehearth_ace.connection:get_disconnected_entities(nil, type)
      dc_count = #entities
      local index = rng:get_int(1, dc_count)
      local entity = entities[index]
      if entity then
         local comp = entity:get_component('stonehearth_ace:vine')
         if comp then
            comp:try_grow()
         end
      end

      if self._sv.disconnected_growth_timers[type] then
         self._sv.disconnected_growth_timers[type]:destroy()
         self._sv.disconnected_growth_timers[type] = nil
      end
   end
   
   if not self._sv.disconnected_growth_timers[type] then
      local period = self:_get_growth_period(type, dc_count)
      if period > 0 then
         self._sv.disconnected_growth_timers[type] = stonehearth.calendar:set_persistent_timer("disconnected vine grow_callback",
               period, function()
                  self:_update_disconnected_growth_timer(type, true)
               end)
      end
   end

   self.__saved_variables:mark_changed()
end

return VineService
