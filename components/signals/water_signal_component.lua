local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_signal')

local get_entities_in_region = radiant.terrain.get_entities_in_region
local get_world_grid_location = radiant.entities.get_world_grid_location

local WaterSignalComponent = class()

function WaterSignalComponent:initialize()
	local json = radiant.entities.get_json(self)
	self._sv._signal_region = json and json.signal_region and Region3(radiant.util.to_cube3(json.signal_region))
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
               self:set_region(Region3(Cube3(Point3.zero))) --", Point3.one" is essentially automatically added by the Cube3 constructor
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
	self._sv.water_exists = nil
	self._sv.water_volume = nil
	self._sv.waterfall_exists = nil
   self._sv.waterfall_volume = nil
   self._sv.water_surface_level = nil
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
	return self._sv.water_exists
end

function WaterSignalComponent:set_water_exists(water_components)
	local exists = next(water_components) ~= nil

	local prev_exists = self._sv.water_exists
	self._sv.water_exists = exists
	
	if exists ~= prev_exists then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:water_exists_changed', exists)
      return true
   end
   return false
end

function WaterSignalComponent:get_water_volume()
	return self._sv.water_volume
end

function WaterSignalComponent:set_water_volume(water_components)
	local volume = 0
	for i, w in pairs(water_components) do
      --volume = volume + w:get_volume()
      volume = volume + self:_get_intersection_volume(w)
	end

	local prev_volume = self._sv.water_volume
	self._sv.water_volume = volume

	if volume ~= prev_volume then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:water_volume_changed', volume)
      return true
   end
   return false
end

function WaterSignalComponent:_get_intersection_volume(water_comp)
   -- self._trans_region gets set by _on_tick_water_signal before this gets called from set_water_volume
   -- apparently regions (at least the way the water component uses them) are integer-bounded
   -- and the top layer region overlaps the main region layer (see commented get_volume() below)
   local location = water_comp:get_location()
   local top_region = water_comp._sv._top_layer:get():translated(location)
   local top_height = water_comp:get_height() % 1
   local base_intersection = self._trans_region:intersect_region(water_comp:get_region():get():translated(location) - top_region)
   local top_intersection = self._trans_region:intersect_region(top_region)
   local volume = base_intersection:get_area() + top_intersection:get_area() * top_height
   return volume
end

--[[
function WaterComponent:get_volume()
   local top = self._sv._top_layer:get()
   local bottom = self._sv.region:get() - top
   local top_height = self._sv.height % 1
   local volume = top_height * top:get_area() + bottom:get_area()
   return volume
end
]]

function WaterSignalComponent:get_water_surface_level()
   return self._sv.water_surface_level
end

function WaterSignalComponent:set_water_surface_level(water_components)
   -- find the highest water level of components in the signal region
   local level
   for i, w in pairs(water_components) do
      local this_level = w:get_water_level()
      if not level then
         level = this_level
      else
         level = math.max(level, this_level)
      end
   end

   if level ~= self._sv.water_surface_level then
      self._sv.water_surface_level = level
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:water_surface_level_changed', level)
      return true
   end
   return false
end

function WaterSignalComponent:get_waterfall_exists()
	return self._sv.waterfall_exists
end

function WaterSignalComponent:set_waterfall_exists(waterfall_components)
	local exists = next(waterfall_components) ~= nil

	local prev_exists = self._sv.waterfall_exists
	self._sv.waterfall_exists = exists
	
	if exists ~= prev_exists then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:waterfall_exists_changed', exists)
      return true
   end
   return false
end

function WaterSignalComponent:get_waterfall_volume()
	return self._sv.waterfall_volume
end

function WaterSignalComponent:set_waterfall_volume(waterfall_components)
	local volume = 0
	for i, w in pairs(waterfall_components) do
		volume = volume + w:get_volume()
	end

	local prev_volume = self._sv.waterfall_volume
	self._sv.waterfall_volume = volume

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
	local location = get_world_grid_location(self._entity)
	if not location then
		self:_reset()
		return
	end
	
	self._trans_region = self._sv._signal_region and self._sv._signal_region:translated(location)
	local water_components, waterfall_components = self:_get_water(self._trans_region)
   local changed = false

   if self:has_monitor_type('water_exists') then
      changed = self:set_water_exists(water_components) or changed
   end
   if self:has_monitor_type('water_volume') then
      changed = self:set_water_volume(water_components) or changed
   end
   if self:has_monitor_type('water_surface_level') then
      changed = self:set_water_surface_level(water_components) or changed
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

	local entities = get_entities_in_region(region)
	local water_components = {}
   local waterfall_components = {}
   local check_water = self:has_monitor_type('water_exists') or self:has_monitor_type('water_volume') or self:has_monitor_type('water_surface_level')
   local check_waterfall = self:has_monitor_type('waterfall_exists') or self:has_monitor_type('waterfall_volume')

	for _, e in pairs(entities) do
      if check_water then
         local water_component = e:get_component('stonehearth:water')
         if water_component then
            table.insert(water_components, water_component)
         end
      end

      if check_waterfall then
         local waterfall_component = e:get_component('stonehearth:waterfall')
         if waterfall_component then
            table.insert(waterfall_components, waterfall_component)
         end
      end
	end

	return water_components, waterfall_components
end

return WaterSignalComponent