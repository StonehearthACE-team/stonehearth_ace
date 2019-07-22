local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

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
   end

   self:reset_changed_on_tick()
end

function AceWaterfallComponent:reset_changed_on_tick()
   self._volume_changed_on_tick = 0
end

function AceWaterfallComponent:was_changed_on_tick()
   return math.abs(self._volume_changed_on_tick) > 0.0001
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

AceWaterfallComponent._ace_old_set_interface = WaterfallComponent.set_interface
function AceWaterfallComponent:set_interface(from_point, to_point)
   self:_cache_location()
   self:_ace_old_set_interface(from_point, to_point)
end

-- override to only consider change if the water component actually changed this tick
function AceWaterfallComponent:_trace_target()
   self:_destroy_target_trace()

   local target = self._sv.target
   if not target then
      return
   end

   self._target_trace = radiant.events.listen(target, 'stonehearth_ace:water:level_changed', self, self._on_target_changed)
   self:_on_target_changed()
end

function AceWaterfallComponent:_on_target_changed(water_level)
   local target = self._sv.target
   if not target or not target:is_valid() then
      return
   end
   
   if not water_level then
      local target_water_component = target:add_component('stonehearth:water')
      water_level = target_water_component:get_water_level()
   end
   
   self._sv.waterfall_bottom.y = water_level

   self:_update_region()
end

-- override this function because it's inefficient; we're caching location now
function AceWaterfallComponent:_update_region()
   local cube = nil

   if self._sv.waterfall_top and self._sv.waterfall_bottom then
      -- top is always integer
      local top = self._sv.waterfall_top.y - self._location.y
      -- bottom may be non-integer since it tracks target water level
      local bottom = math.floor(self._sv.waterfall_bottom.y) - self._location.y

      if bottom > top then
         bottom = top
      end

      cube = Cube3(Point3.zero)
      cube.max.y = top
      cube.min.y = bottom
   end

   if self:_is_region_different(cube, self._sv.cube) then
      self._sv.region:modify(function(cursor)
         cursor:clear()

         if cube then
            cursor:add_cube(cube)
         end
      end)
      
      self._entity:add_component('region_collision_shape'):set_region(self._sv.region)

      local destination_comp = self._entity:get_component('destination')
      if not destination_comp then
         destination_comp = self._entity:add_component('destination')
         destination_comp:set_region(_radiant.sim.alloc_region3())
         destination_comp:set_auto_update_adjacent(true)
      end
      destination_component:get_region():modify(function(cursor)
         cursor:clear()
         if cube then
            cursor:add_cube(cube)
         end
      end)

      stonehearth_ace.water_signal:waterfall_component_modified(self._entity)
   end

   self.__saved_variables:mark_changed()
end

function AceWaterfallComponent:_is_region_different(c1, c2)
   -- we only care about a difference of existence or a difference of y values
   return (c1 == nil) ~= (c2 == nil) or 
         (c1 ~= nil and
            (c1.min.y ~= c2.min.y or c1.max.y ~= c2.max.y))
end

function AceWaterfallComponent:_cache_location()
   self._location = radiant.entities.get_world_grid_location(self._entity)

   stonehearth_ace.water_signal:waterfall_component_modified(self._entity)
end

return AceWaterfallComponent
