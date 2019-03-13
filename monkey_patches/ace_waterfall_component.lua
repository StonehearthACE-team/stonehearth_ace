local log = radiant.log.create_logger('waterfall')

local WaterfallComponent = require 'stonehearth.components.waterfall.waterfall_component'
local AceWaterfallComponent = class()

function WaterfallComponent:restore()
   self._is_restore = true
end

AceWaterfallComponent._ace_old_activate = WaterfallComponent.activate
function AceWaterfallComponent:activate()
   self:_ace_old_activate()

   if self._is_restore then
      self:_cache_location()
   else
      self._parent_trace = self._entity:add_component('mob'):trace_parent('waterfall added to world', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function(parent_entity)
            if parent_entity then
               --we were just added to the world
               self._parent_trace:destroy()
               self:_cache_location()
            end
         end)
   end

   self:reset_changed_on_tick()
end

function AceWaterfallComponent:reset_changed_on_tick()
   self._volume_changed_on_tick = 0
   self._top_on_tick = self._sv.waterfall_top
   self._bottom_on_tick = self._sv.waterfall_bottom
end

function AceWaterfallComponent:was_changed_on_tick()
   if math.abs(self._volume_changed_on_tick) > 0.0001 then
      --log:debug('%s volume changed by %d', self._entity, self._volume_changed_on_tick)
      return true
   end
   if (self._bottom_on_tick ~= nil) ~= (self._sv.waterfall_bottom ~= nil) then
      --log:debug('%s bottom point changed', self._entity)
      return true
   end
   if self._top_on_tick ~= self._sv.waterfall_top then
      --log:debug('%s top point changed', self._entity)
      return true
   end
   if self._bottom_on_tick and (self._bottom_on_tick.x ~= self._sv.waterfall_bottom.x or 
         self._bottom_on_tick.z ~= self._sv.waterfall_bottom.z or 
         math.floor(self._bottom_on_tick.y) ~= math.floor(self._sv.waterfall_bottom.y)) then
      --log:debug('%s bottom point changed from %s to %s', self._entity, self._bottom_on_tick, self._sv.waterfall_bottom)
      return true
   end
   return false
end

function AceWaterfallComponent:get_location()
   return self._location
end

function AceWaterfallComponent:set_volume(volume)
   if volume == self._sv.volume then
      return
   end

   self._volume_changed_on_tick = self._volume_changed_on_tick + (self._sv.volume or 0) - volume

   self._sv.volume = volume
   self.__saved_variables:mark_changed()

   stonehearth_ace.water_signal:waterfall_component_modified(self._entity, true)
end

AceWaterfallComponent._ace_old__update_region = WaterfallComponent._update_region
function AceWaterfallComponent:_update_region()
   self:_ace_old__update_region()

   self._entity:add_component('region_collision_shape'):set_region(self._sv.region)
   self:_cache_location()
end

function AceWaterfallComponent:_cache_location()
   self._location = radiant.entities.get_world_grid_location(self._entity)

   stonehearth_ace.water_signal:waterfall_component_modified(self._entity, true)
end

return AceWaterfallComponent
