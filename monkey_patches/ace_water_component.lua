local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('water')

local WaterComponent = require 'stonehearth.components.water.water_component'
local AceWaterComponent = class()

AceWaterComponent._old_activate = WaterComponent.activate
function AceWaterComponent:activate()
   self:_old_activate()

   self:_update_pathing()
end

function AceWaterComponent:update_pathable_region()
   if self._sv.region and (not self._sv.last_updated_pathable_region or not self._sv.last_updated_pathable_region:equals(self._sv.region:get())) then
      -- only add it to the horizontal layer of water that's one voxel down from the top
      local region = self._sv.region:get():extruded('y', 0, -1)
      local bounds = region:get_bounds()
      region:subtract_region(Region3(bounds):extruded('y', 0, -1))

      region:optimize('water pathing')
      self._entity:add_component('stonehearth_ace:vertical_pathing_region'):set_region(region)
      self._sv.last_updated_pathable_region = self._sv.region:get()
      self.__saved_variables:mark_changed()
   end
end

function AceWaterComponent:get_volume_info()
   if not self._calculated_up_to_date then
      local location = self._location
      local top_region = self._sv._top_layer:get():translated(location)
      local top_height = self._sv.height % 1
      local base_region = self._sv.region:get():translated(location) - top_region
      self._calculated_volume_info = {
         base_region = base_region,
         top_region = top_region,
         top_height = top_height
      }
      self._calculated_up_to_date = true
   end
   return self._calculated_volume_info
end

-- this is used instead of evaporate() so that it only triggers on actual evaporation
AceWaterComponent._old__remove_from_wetting_layer = WaterComponent._remove_from_wetting_layer
function AceWaterComponent:_remove_from_wetting_layer(num_blocks)
   local value = self:_old__remove_from_wetting_layer(num_blocks)

   if num_blocks > 0 then
      stonehearth_ace.water_signal:water_component_modified(self._entity)
   end

   return value
end

AceWaterComponent._old_add_water = WaterComponent.add_water
function AceWaterComponent:add_water(volume, add_location)
   local volume, info = self:_old_add_water(volume, add_location)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity)

   return volume, info
end

AceWaterComponent._old_remove_water = WaterComponent.remove_water
function AceWaterComponent:remove_water(volume, clamp)
   local volume = self:_old_remove_water(volume, clamp)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity)

   return volume
end

AceWaterComponent._old_merge_with = WaterComponent.merge_with
function AceWaterComponent:merge_with(mergee, allow_uneven_top_layers)
   self:_old_merge_with(mergee, allow_uneven_top_layers)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity)
   stonehearth_ace.water_signal:water_component_modified(mergee)
end

AceWaterComponent._old_set_region = WaterComponent.set_region
function AceWaterComponent:set_region(boxed_region, height)
   self:_old_set_region(boxed_region, height)

   self._calculated_up_to_date = false
   stonehearth_ace.water_signal:water_component_modified(self._entity)
   self:_update_pathing()
end

function AceWaterComponent:_update_pathing()
   -- if we want to enable vertical pathing in water regions, this is where we do that (or queue it)
   -- updates to large/complex water bodies can potentially cause lag
   -- entities tend to walk on water for a bit before getting low enough to trigger their swimming animation
   --stonehearth_ace.water_signal:water_component_pathing_modified(self._entity)
end

return AceWaterComponent
