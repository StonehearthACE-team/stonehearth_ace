--[[
   A water wheel provides mechanical power through proximity to water. It has up to 3 water signals:
      - low horizontal, allowing for some minimal power generation
      - clockwise vertical, checking for waterfalls that would make the wheel turn clockwise in its default orientation
      - counterclockwise vertical, checking for waterfalls that would make the wheel turn counterclockwise in its default orientation
]]

local ConnectionUtils = require 'lib.connection.connection_utils'
local BOTTOM = 'water_wheel:bottom'
local CLOCKWISE = 'water_wheel:clockwise'
local COUNTERCLOCKWISE = 'water_wheel:counterclockwise'

local WaterWheelComponent = class()

function WaterWheelComponent:initialize()
   local json = radiant.entities.get_json(self)
   self._json = json or {}
   
   self._max_bottom_volume = 1
   self._max_produced_bottom = math.min(1, self._json.max_produced_bottom or 0.5)
   self._max_produced_side_volume = math.min(1, self._json.max_produced_side_volume or 10)

   self._sv.produce_percent = 0
   self._sv.bottom_percent = 0
   self._sv.clockwise_percent = 0
   self._sv.counterclockwise_percent = 0
end

function WaterWheelComponent:activate()
   -- set up water signals on the appropriate regions
   local regions = self._json.signal_regions
   if regions then
      local ws = self._entity:add_component('stonehearth_ace:water_signal')
      
      if regions.bottom then
         local r = ConnectionUtils.import_region(regions.bottom)
         self._max_bottom_volume = math.max(1, r:get_area())
         self._bottom_signal = ws:set_signal(BOTTOM, r, {'water_volume'},
            function(changes)
               self:_bottom_changed(changes)
            end)
      else
         ws:remove_signal(BOTTOM)
      end

      if regions.clockwise then
         local r = ConnectionUtils.import_region(regions.clockwise)
         self._clockwise_signal = ws:set_signal(CLOCKWISE, r, {'waterfall_volume'},
            function(changes)
               self:_clockwise_changed(changes)
            end)
      else
         ws:remove_signal(CLOCKWISE)
      end

      if regions.counterclockwise then
         local r = ConnectionUtils.import_region(regions.counterclockwise)
         self._counterclockwise_signal = ws:set_signal(COUNTERCLOCKWISE, r, {'waterfall_volume'},
            function(changes)
               self:_counterclockwise_changed(changes)
            end)
      else
         ws:remove_signal(COUNTERCLOCKWISE)
      end
   end
end

function WaterWheelComponent:_bottom_changed(changes)
   if changes.water_volume.value then
      local percent = changes.water_volume.value / self._max_bottom_volume
      self._sv.bottom_percent = percent
      self.__saved_variables:mark_changed()

      self:_reconsider_production()
   end
end

function WaterWheelComponent:_clockwise_changed(changes)
   if changes.waterfall_volume.value then
      local percent = changes.waterfall_volume.value / self._max_produced_side_volume
      self._sv.clockwise_percent = percent
      self.__saved_variables:mark_changed()

      self:_reconsider_production()
   end
end

function WaterWheelComponent:_counterclockwise_changed(changes)
   if changes.waterfall_volume.value then
      local percent = changes.waterfall_volume.value / self._max_produced_side_volume
      self._sv.counterclockwise_percent = percent
      self.__saved_variables:mark_changed()

      self:_reconsider_production()
   end
end

function WaterWheelComponent:_reconsider_production()
   -- bottom power produces at most a certain percent of max potential
   -- side power cancels out opposites
   local production = self._max_produced_bottom * self._sv.bottom_percent
   local side_production = math.min(1, math.abs(self._sv.clockwise_percent - self._sv.counterclockwise_percent) / self._max_produced_side_volume)
   local should_reverse = self._sv.clockwise_percent < self._sv.counterclockwise_percent and side_production > production

   self._entity:add_component('stonehearth_ace:mechanical'):set_power_produced_percent(math.max(production, side_production), should_reverse)
end

return WaterWheelComponent