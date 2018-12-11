local log = radiant.log.create_logger('water')

local WaterComponent = require 'stonehearth.components.water.water_component'
local AceWaterComponent = class()

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

   stonehearth_ace.water_signal:water_component_modified(self._entity)

   return volume, info
end

AceWaterComponent._old_remove_water = WaterComponent.remove_water
function AceWaterComponent:remove_water(volume, clamp)
   local volume = self:_old_remove_water(volume, clamp)

   stonehearth_ace.water_signal:water_component_modified(self._entity)

   return volume
end

AceWaterComponent._old_merge_with = WaterComponent.merge_with
function AceWaterComponent:merge_with(mergee, allow_uneven_top_layers)
   self:_old_merge_with(mergee, allow_uneven_top_layers)

   stonehearth_ace.water_signal:water_component_modified(self._entity)
   stonehearth_ace.water_signal:water_component_modified(mergee)
end

AceWaterComponent._old_set_region = WaterComponent.set_region
function AceWaterComponent:set_region(boxed_region, height)
   self:_old_set_region(boxed_region, height)

   stonehearth_ace.water_signal:water_component_modified(self._entity)
end

return AceWaterComponent
