local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_signal')

local WaterSignalComponent = class()

function WaterSignalComponent:initialize()
	local json = radiant.entities.get_json(self)
	self._signal_region = Region3(json.signal_region)
end

function WaterSignalComponent:post_activate()
   self._tick_listener = radiant.events.listen(stonehearth.hydrology, 'stonehearth:hydrology:tick', function()
         self:_on_tick()
      end)
end

function WaterSignalComponent:destroy()
	if self._tick_listener then
		self._tick_listener:destroy()
		self._tick_listener = nil
	end
end

function WaterSignalComponent:_reset()
	if self._sv._water_exists then
		self._sv._water_exists = nil
		self._sv._water_volume = nil
		self._sv._waterfall_exists = nil
		self._sv._waterfall_volume = nil
		self.__saved_variables:mark_changed()
	end
end

function WaterSignalComponent:get_water_exists()
	return self._sv._water_exists
end

function WaterSignalComponent:set_water_exists(water_entities)
	local exists = #water_entities > 0

	self._water_last_exists = self._sv._water_exists
	self._sv._water_exists = exists
	
	-- only trigger change event if it's different than the last two ticks
	-- to prevent constant triggers on alternating existence per tick
	if exists ~= self._sv._water_exists and exists ~= self._water_last_exists then
		self.__saved_variables:mark_changed()
		radiant.events.trigger(self._entity, 'water_signal:water_exists_changed', exists)
	end
end

function WaterSignalComponent:get_water_volume()
	return self._sv._water_volume
end

function WaterSignalComponent:set_water_volume(water_entities)
	local volume = 0
	for i, w in pairs(water_entities) do
		volume = volume + w:get_volume()
	end

	self._water_last_volume = self._sv._water_volume
	self._sv._water_volume = volume

	-- only trigger change event if it's different than the last two ticks
	-- to prevent constant triggers on alternating volume per tick
	if volume ~= self._sv._water_volume and volume ~= self._water_last_volume then
		self.__saved_variables:mark_changed()
		radiant.events.trigger(self._entity, 'water_signal:water_volume_changed', volume)
	end
end

function WaterSignalComponent:get_waterfall_exists()
	return self._sv._waterfall_exists
end

function WaterSignalComponent:set_waterfall_exists(waterfall_components)
	local exists = #waterfall_components > 0

	self._waterfall_last_exists = self._sv._waterfall_exists
	self._sv._waterfall_exists = exists
	
	-- only trigger change event if it's different than the last two ticks
	-- to prevent constant triggers on alternating existence per tick
	if exists ~= self._sv._waterfall_exists and exists ~= self._waterfall_last_exists then
		self.__saved_variables:mark_changed()
		radiant.events.trigger(self._entity, 'water_signal:waterfall_exists_changed', exists)
	end
end

function WaterSignalComponent:get_waterfall_volume()
	return self._sv._waterfall_volume
end

function WaterSignalComponent:set_waterfall_volume(waterfall_entities)
	local volume = 0
	for i, w in pairs(waterfall_entities) do
		volume = volume + w:get_volume()
	end

	self._waterfall_last_volume = self._sv._waterfall_volume
	self._sv._waterfall_volume = volume

	-- only trigger change event if it's different than the last two ticks
	-- to prevent constant triggers on alternating volume per tick
	if volume ~= self._sv._waterfall_volume and volume ~= self._waterfall_last_volume then
		self.__saved_variables:mark_changed()
		radiant.events.trigger(self._entity, 'water_signal:waterfall_volume_changed', volume)
	end
end

function WaterSignalComponent:_on_tick()
	-- do we really need to update the water regions we're checking every single tick?
	-- not sure how expensive this is
	local location = radiant.entities:get_world_grid_location(self._entity)
	if not location then
		self:_reset()
		return
	end
	
	local region = self._signal_region + location
	local water_components, waterfall_components = _get_water(region)

	self:set_water_exists(water_components)
	self:set_water_volume(water_components)
	self:set_waterfall_exists(waterfall_components)
	self:set_waterfall_volume(waterfall_components)
end

function WaterSignalComponent:_get_water(region)
	if not region then
		return {}
	end

	local entities = radiant.terrain.get_entities_in_region(region)
	local water_components = {}
	local waterfall_components = {}
	for _, e in pairs(entities) do
		local water_component = e:get_component('stonehearth:water')
		if water_component then
			table.insert(water_components, water_component)
		end

		local waterfall_component = e:get_component('stonehearth:waterfall')
		if waterfall_component then
			table.insert(waterfall_components, waterfall_component)
		end
	end

	return water_components, waterfall_components
end

return WaterSignalComponent