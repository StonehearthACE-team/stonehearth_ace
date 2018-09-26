local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_signal')

local WaterSignalComponent = class()

function WaterSignalComponent:initialize()
	local json = radiant.entities.get_json(self)
	self._sv._signal_region = json and json.signal_region and Region3(json.signal_region)
   self._sv.is_urgent = json and json.is_urgent or false
   self._sv.monitor_types = {}
   if json and json.monitor_types then
      self:add_monitor_types(json.monitor_types)
   else
      -- default to monitoring nothing
   end
	self.__saved_variables:mark_changed()
end

function WaterSignalComponent:create()
	self._is_create = true
end

function WaterSignalComponent:post_activate()
	if self._is_create then
		if not self._sv._signal_region then
			local component = self._entity:get_component('region_collision_shape')
			if component then
            self:set_region(component:get_region():get())
         else
            component = self._entity:get_component('destination')
            if component then
               self:set_region(component:get_region():get())
            else
               self:set_region(Region3(Cube3(Point3.zero, Point3.one)))
            end
         end
      end
   elseif not self._sv.monitor_types then
      -- backwards compatibility with existing water signals that monitored everything
      self._sv.monitor_types = {}
      self:add_monitor_types(stonehearth.constants.water_signal.MONITOR_TYPES)
	end
	self:_startup()
end

function WaterSignalComponent:destroy()
	self:_shutdown()
end

function WaterSignalComponent:_startup()
	stonehearth_ace.water_signal:register_water_signal(self, self._sv.is_urgent)
end

function WaterSignalComponent:_shutdown()
	stonehearth_ace.water_signal:unregister_water_signal(self)
end

function WaterSignalComponent:_reset()
	self._sv._water_exists = nil
	self._sv._water_volume = nil
	self._sv._waterfall_exists = nil
   self._sv._waterfall_volume = nil
	self.__saved_variables:mark_changed()
end

function WaterSignalComponent:get_entity_id()
	return self._entity:get_id()
end

function WaterSignalComponent:set_region(region)
	self._sv._signal_region = region
	self:_reset()
end

function WaterSignalComponent:set_urgency(is_urgent)
	if is_urgent ~= self._sv.is_urgent then
		self._sv.is_urgent = is_urgent
		self:_shutdown()
		self:_startup()
	end
end

function WaterSignalComponent:has_monitor_type(monitor_type)
   return self._sv.monitor_types[monitor_type] ~= nil
end

-- should these be filtered on stonehearth.constants.water_signal.MONITOR_TYPES?
function WaterSignalComponent:add_monitor_types(monitor_types)
   for _, monitor_type in ipairs(monitor_types) do
      self._sv.monitor_types[monitor_type] = true
   end
	self.__saved_variables:mark_changed()
end

function WaterSignalComponent:remove_monitor_types(monitor_types)
   if monitor_types then
      for _, monitor_type in ipairs(monitor_types) do
         self._sv.monitor_types[monitor_type] = nil
      end
   else
      -- if we passed in nil, clear out the whole thing
      self._sv.monitor_types = {}
   end
	self.__saved_variables:mark_changed()
end

function WaterSignalComponent:get_water_exists()
	return self._sv._water_exists
end

function WaterSignalComponent:set_water_exists(water_entities)
	local exists = next(water_entities) ~= nil

	local prev_exists = self._sv._water_exists
	self._sv._water_exists = exists
	
	if exists ~= prev_exists then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:water_exists_changed', exists)
      return true
   end
   return false
end

function WaterSignalComponent:get_water_volume()
	return self._sv._water_volume
end

function WaterSignalComponent:set_water_volume(water_entities)
	local volume = 0
	for i, w in pairs(water_entities) do
		volume = volume + w:get_volume()
	end

	local prev_volume = self._sv._water_volume
	self._sv._water_volume = volume

	if volume ~= prev_volume then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:water_volume_changed', volume)
      return true
   end
   return false
end

function WaterSignalComponent:get_waterfall_exists()
	return self._sv._waterfall_exists
end

function WaterSignalComponent:set_waterfall_exists(waterfall_components)
	local exists = next(waterfall_components) ~= nil

	local prev_exists = self._sv._waterfall_exists
	self._sv._waterfall_exists = exists
	
	if exists ~= prev_exists then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:waterfall_exists_changed', exists)
      return true
   end
   return false
end

function WaterSignalComponent:get_waterfall_volume()
	return self._sv._waterfall_volume
end

function WaterSignalComponent:set_waterfall_volume(waterfall_entities)
	local volume = 0
	for i, w in pairs(waterfall_entities) do
		volume = volume + w:get_volume()
	end

	local prev_volume = self._sv._waterfall_volume
	self._sv._waterfall_volume = volume

	if volume ~= prev_volume then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:waterfall_volume_changed', volume)
      return true
   end
   return false
end

function WaterSignalComponent:_on_tick_water_signal()
	if not self._sv._signal_region or not next(self._sv.monitor_types) then
		return
	end
	
	-- do we really need to update the water regions we're checking every single tick?
	-- not sure how expensive this is
	local location = radiant.entities.get_world_grid_location(self._entity)
	if not location then
		self:_reset()
		return
	end
	
	local region = self._sv._signal_region and self._sv._signal_region:translated(location)
	local water_components, waterfall_components = self:_get_water(region)
   local changed = false

   if self:has_monitor_type('water_exists') then
      changed = self:set_water_exists(water_components) or changed
   end
   if self:has_monitor_type('water_volume') then
      changed = self:set_water_volume(water_components) or changed
   end
   if self:has_monitor_type('waterfall_exists') then
      changed = self:set_waterfall_exists(waterfall_components) or changed
   end
   if self:has_monitor_type('waterfall_volume') then
      changed = self:set_waterfall_volume(waterfall_components) or changed
   end
   
   if changed then
      self.__saved_variables:mark_changed()
   end
end

function WaterSignalComponent:_get_water(region)
	if not region then
		return {}, {}
	end

	local entities = radiant.terrain.get_entities_in_region(region)
	local water_components = {}
	local waterfall_components = {}
	for _, e in pairs(entities) do
      if self:has_monitor_type('water_exists') or self:has_monitor_type('water_volume') then
         local water_component = e:get_component('stonehearth:water')
         if water_component then
            table.insert(water_components, water_component)
         end
      end

      if self:has_monitor_type('waterfall_exists') or self:has_monitor_type('waterfall_volume') then
         local waterfall_component = e:get_component('stonehearth:waterfall')
         if waterfall_component then
            table.insert(waterfall_components, waterfall_component)
         end
      end
	end

	return water_components, waterfall_components
end

return WaterSignalComponent