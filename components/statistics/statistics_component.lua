--[[
   simple component for recording and modifying numerical statistics
]]

local StatisticsComponent = class()

function StatisticsComponent:initialize()
   self._sv.statistics = {}
end

function StatisticsComponent:get_category_stats(category)
   return self._sv.statistics[category]
end

function StatisticsComponent:get_stat(category, name, default)
   local category_stats = self._sv.statistics[category]
   return category_stats and category_stats[name] or default
end

function StatisticsComponent:set_stat(category, name, value)
   self:_add_stat(category, name, value)
end

function StatisticsComponent:increment_stat(category, name, value, default)
   local prev_value = self:_add_stat(category, name) or default or 0
   self._sv.statistics[category][name] = prev_value + (value or 1)
   self.__saved_variables:mark_changed()
end

function StatisticsComponent:_add_stat(category, name, value)
   local category_stats = self._sv.statistics[category]
   if not category_stats then
      category_stats = {}
      self._sv.statistics[category] = category_stats
   end
   if value then
      category_stats[name] = value
      self.__saved_variables:mark_changed()
   end

   return category_stats[name]
end

return StatisticsComponent