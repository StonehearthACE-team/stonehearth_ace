local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_signal')

local WaterSignalComponent = class()

function WaterSignalComponent:initialize()
	local json = radiant.entities.get_json(self)
	self._signal_region = Region3(json.signal_region)
	self._exists = nil
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

function WaterSignalComponent:get_exists()
	return self._exists
end

function WaterSignalComponent:set_exists(count)
	local exists = count > 0

	self._last_exists = self._exists
	self._exists = exists
	
	-- only trigger change event if it's different than the last two ticks
	-- to prevent constant triggers on alternating existence per tick
	if exists ~= self._exists and exists ~= self._last_exists then
	if exists ~= self._exists then
		radiant.events.trigger(self._entity, 'water_signal_exists_changed', exists)
	end
end

function WaterSignalComponent:get_volume()
	return self._volume
end

function WaterSignalComponent:set_volume(water_entities)
	local volume = 0
	for i, w in pairs(water_entities) do
		volume = volume + w:get_volume()
	end

	self._last_volume = self._volume
	self._volume = volume

	-- only trigger change event if it's different than the last two ticks
	-- to prevent constant triggers on alternating volume per tick
	if volume ~= self._volume and volume ~= self._last_volume then
		radiant.events.trigger(self._entity, 'water_signal_volume_changed', volume)
	end
end

function WaterSignalComponent:_on_tick()
	-- do we really need to update the water regions we're checking every single tick?
	-- not sure how expensive this is
	local water_components = _get_water(self._signal_region)

	self:set_exists(#water_components)
	self:set_volume(water_components)
end

function WaterSignalComponent:_get_water(region)
	if not region then
		return {}
	end

	local entities = radiant.terrain.get_entities_in_region(region)
	local water_components = {}
	for i, e in pairs(entities) do
		local water_component = e:get_component('stonehearth:water')
		if e then
			water_components[#water_regions + 1] = water_component
		end
	end

	return water_components
end

return WaterSignalComponent