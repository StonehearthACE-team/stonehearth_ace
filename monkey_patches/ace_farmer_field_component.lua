local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('farmer_field')
local FarmerFieldComponent = require 'stonehearth.components.farmer_field.farmer_field_component'

local AceFarmerFieldComponent = class()

local RECALCULATE_THRESHOLD = 0.5

AceFarmerFieldComponent._old_restore = FarmerFieldComponent.restore
function AceFarmerFieldComponent:restore()
	self:_old_restore()

   self._is_restore = true
end

AceFarmerFieldComponent._old_on_field_created = FarmerFieldComponent.on_field_created
function AceFarmerFieldComponent:on_field_created(town, size)
	self:_old_on_field_created(town, size)

	self:_create_water_listener()
end

function AceFarmerFieldComponent:post_activate()
   if self._is_restore then
      self:_create_water_listener()
   end
end

AceFarmerFieldComponent._old_plant_crop_at = FarmerFieldComponent.plant_crop_at
function FarmerFieldComponent:plant_crop_at(x_offset, z_offset)
	local crop = self:_old_plant_crop_at(x_offset, z_offset)

	if crop then
		crop:add_component('stonehearth:growing'):set_water_level(self._sv.water_level or 0)
	end
end

function AceFarmerFieldComponent:_create_water_listener()
	if self._water_listener then
		self:_destroy_water_listener()
	end

	local region = self._entity:get_component('region_collision_shape'):get_region():get()
						:extruded('x', 1, 1)
                  :extruded('z', 1, 1)
                  :extruded('y', 1, 0)
   local water_component = self._entity:add_component('stonehearth_ace:water_signal')
   self._water_signal = water_component:set_signal('farmer_field', region, {'water_volume'}, function(changes) self:_on_water_signal_changed(changes) end)
   self._sv.water_signal_region = region:duplicate()
   self:_set_water_volume(self._water_signal:get_water_volume())
end

function AceFarmerFieldComponent:_destroy_water_listener()
	if self._water_listener then
		self._water_listener:destroy()
		self._water_listener = nil
	end
end

function AceFarmerFieldComponent:_set_water_volume(volume)
   if volume then
      -- we consider the normal ideal water volume to crop ratio to be a filled half perimeter around an 11x11 farm of 66 crops
      -- i.e., 24 water / 66 crops = 4/11
      -- we compare that to our current volume to crop ratio
      local ideal_ratio = 4/11
      local this_ratio = volume / (math.ceil(self._sv.size.x/2) * self._sv.size.y)
      self._sv.water_level = this_ratio / ideal_ratio
   else
      self._sv.water_level = 0
   end
	self.__saved_variables:mark_changed()
end

function AceFarmerFieldComponent:_on_water_signal_changed(changes)
   local volume = changes.water_volume.value
   if not volume then
      return
   end
   
   self:_set_water_volume(volume)

	if self:_is_fallow() then
		return
	end

   -- if the water level only changed by a tiny bit, we don't want to recalculate water levels for everything
   -- once the change meets a particular threshold, go ahead and propogate
   local last_calculated = self._sv.last_calculated_water_volume
   if last_calculated and math.abs(last_calculated - volume) < RECALCULATE_THRESHOLD then
      return
   end

   self._sv.last_calculated_water_volume = volume
   self.__saved_variables:mark_changed()

	for x=1, self._sv.size.x do
		for y=1, self._sv.size.y do
			local dirt_plot = self._sv.contents[x][y]
			if dirt_plot and dirt_plot.contents then
				dirt_plot.contents:add_component('stonehearth:growing'):set_water_level(self._sv.water_level)
			end
		end
	end
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceFarmerFieldComponent:get_best_water_level()
	if self:_is_fallow() then
		return nil
	end
	
	local json = radiant.resources.load_json(self._sv.current_crop_alias)
	self._preferred_climate = json and json.preferred_climate
	return stonehearth.town:get_best_water_level_from_climate(self._preferred_climate)
end

AceFarmerFieldComponent._old__on_destroy = FarmerFieldComponent._on_destroy
function AceFarmerFieldComponent:_on_destroy()
	self:_old__on_destroy()

	self:_destroy_water_listener()
end

return AceFarmerFieldComponent
