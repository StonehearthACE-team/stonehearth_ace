--[[
   simple component for recording and modifying numerical/list statistics
]]

local StatisticsComponent = class()

function StatisticsComponent:initialize()
   self._sv._statistics = {}
end

-- switch to statistics being private to reduce network usage (esp. in multiplayer/combat situations)
function StatisticsComponent:restore()
   if self._sv.statistics then
      self._sv._statistics = self._sv.statistics
      self._sv.statistics = nil
   end
end

-- used by reembarking
function StatisticsComponent:get_statistics()
   return self._sv._statistics
end

function StatisticsComponent:set_statistics(statistics)
   self._sv._statistics = statistics or {}
   --self.__saved_variables:mark_changed()
end

function StatisticsComponent:get_category_stats(category)
   return self._sv._statistics[category]
end

function StatisticsComponent:get_stat(category, name, default)
   local category_stats = self._sv._statistics[category]
   return category_stats and category_stats[name] or default
end

function StatisticsComponent:set_stat(category, name, value)
   self:_add_stat(category, name, value)
end

-- it's up to the caller to make sure that they're adding/incrementing stats of the right types
function StatisticsComponent:increment_stat(category, name, value, default)
   local prev_value = self:_add_stat(category, name) or default or 0
   value = prev_value + (value or 1)
   self._sv._statistics[category][name] = value
   --self.__saved_variables:mark_changed()

   self:_trigger_on_changed(category, name, value)
end

function StatisticsComponent:add_to_stat_list(category, name, value, default)
   local prev_value = self:_add_stat(category, name)
   if not prev_value then
      prev_value = default or {}
      self._sv._statistics[category][name] = prev_value
   end
   table.insert(prev_value, value)
   --self.__saved_variables:mark_changed()

   self:_trigger_on_changed(category, name, value)
end

function StatisticsComponent:_add_stat(category, name, value)
   local category_stats = self._sv._statistics[category]
   if not category_stats then
      category_stats = {}
      self._sv._statistics[category] = category_stats
   end
   if value then
      category_stats[name] = value
      --self.__saved_variables:mark_changed()
   end

   return category_stats[name]
end

-- trigger_async because they're not urgent and stats should always be increasing, so it shouldn't matter if you get them out of order
function StatisticsComponent:_trigger_on_changed(category, name, value)
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:stat_changed', {
      category = category,
      name = name,
      value = value
   })
end

return StatisticsComponent