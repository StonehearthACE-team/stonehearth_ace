local get_entities_in_region = radiant.terrain.get_entities_in_region
local get_world_grid_location = radiant.entities.get_world_grid_location
local log = radiant.log.create_logger('water_signal')

local WaterSignal = class()

function WaterSignal:initialize()
   self._sv.signal_region = nil
   self._sv.monitor_types = {}
   self._change_cb = nil
end

function WaterSignal:create(entity, signal_region, monitor_types, change_callback)
   self._sv.entity = entity
   self:set_settings(signal_region, monitor_types, change_callback)
end

function WaterSignal:_reset()
   log:debug('resetting water signal for entity %s', self._sv.entity)
   self._sv.water_exists = nil
	self._sv.water_volume = nil
	self._sv.waterfall_exists = nil
   self._sv.waterfall_volume = nil
   self._sv.water_surface_level = nil
	self.__saved_variables:mark_changed()
end

function WaterSignal:set_settings(signal_region, monitor_types, change_callback)
   self:set_signal_region(signal_region)
   self:add_monitor_types(monitor_types)
   self:set_change_callback(change_callback)

   self:_on_tick_water_signal()
end

function WaterSignal:get_signal_region()
   return self._sv.signal_region
end

function WaterSignal:set_signal_region(signal_region)
   self._sv.signal_region = signal_region
   self.__saved_variables:mark_changed()
end

function WaterSignal:has_monitor_type(monitor_type)
   return self._sv.monitor_types[monitor_type] ~= nil
end

function WaterSignal:get_monitor_types()
   return radiant.shallow_copy(self._sv.monitor_types)
end

function WaterSignal:set_monitor_types(monitor_types)
   local changed = false
   local types = {}
   for _, monitor_type in ipairs(monitor_types) do
      types[monitor_type] = true
      if not self._sv.monitor_types[monitor_type] then
         changed = true
         self._sv.monitor_types[monitor_type] = true
      end
   end
   for monitor_type, _ in pairs(self._sv.monitor_types) do
      if not types[monitor_type] then
         changed = true
         self._sv.monitor_types[monitor_type] = nil
      end
   end

   if changed then
      self:_reset()
   end
end

-- should these be filtered on stonehearth.constants.water_signal.MONITOR_TYPES?
function WaterSignal:add_monitor_types(monitor_types)
   local changed = false
   for _, monitor_type in ipairs(monitor_types) do
      if not self._sv.monitor_types[monitor_type] then
         changed = true
         self._sv.monitor_types[monitor_type] = true
      end
   end

   if changed then
      self:_reset()
   end
end

function WaterSignal:remove_monitor_types(monitor_types)
   local changed = false
   if monitor_types then
      for _, monitor_type in ipairs(monitor_types) do
         if self._sv.monitor_types[monitor_type] then
            changed = true
            self._sv.monitor_types[monitor_type] = nil
         end
      end
   elseif next(self._sv.monitor_types) then
      -- if we passed in nil, clear out the whole thing
      changed = true
      self._sv.monitor_types = {}
   end

	if changed then
      self:_reset()
   end
end

function WaterSignal:set_change_callback(f_cb)
   if f_cb == nil or type(f_cb) == 'function' then
      self._change_cb = f_cb
   end
end

function WaterSignal:get_water_exists()
	return self._sv.water_exists
end

function WaterSignal:set_water_exists(water_components)
	local exists = next(water_components) ~= nil

	local prev_exists = self._sv.water_exists
	self._sv.water_exists = exists
	
	if exists ~= prev_exists then
      return true
   end
   return false
end

function WaterSignal:get_water_volume()
	return self._sv.water_volume
end

function WaterSignal:set_water_volume(water_components)
	local volume = 0
	for i, w in pairs(water_components) do
      --volume = volume + w:get_volume()
      volume = volume + self:_get_intersection_volume(w)
	end

	local prev_volume = self._sv.water_volume
	self._sv.water_volume = volume

	if volume ~= prev_volume then
      return true
   end
   return false
end

function WaterSignal:_get_intersection_volume(water_comp)
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

function WaterSignal:get_water_surface_level()
   return self._sv.water_surface_level
end

function WaterSignal:set_water_surface_level(water_components)
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
      return true
   end
   return false
end

function WaterSignal:get_waterfall_exists()
	return self._sv.waterfall_exists
end

function WaterSignal:set_waterfall_exists(waterfall_components)
	local exists = next(waterfall_components) ~= nil

	local prev_exists = self._sv.waterfall_exists
	self._sv.waterfall_exists = exists
	
	if exists ~= prev_exists then
      return true
   end
   return false
end

function WaterSignal:get_waterfall_volume()
	return self._sv.waterfall_volume
end

function WaterSignal:set_waterfall_volume(waterfall_components)
	local volume = 0
	for i, w in pairs(waterfall_components) do
		volume = volume + w:get_volume()
	end

	local prev_volume = self._sv.waterfall_volume
	self._sv.waterfall_volume = volume

	if volume ~= prev_volume then
      return true
   end
   return false
end

function WaterSignal:_on_tick_water_signal()
	if not self._sv.signal_region or not next(self._sv.monitor_types) then
		return
	end
	
	-- do we really need to update the water regions we're checking every single tick?
	-- not sure how expensive this is
	local location = get_world_grid_location(self._sv.entity)
	if not location then
		self:_reset()
		return
	end
   
   --log:debug('on_tick for %s with signal_region %s', self._sv.entity, type(self._sv.signal_region) == 'table' and radiant.util.table_tostring(self._sv.signal_region) or 'NIL')
	self._trans_region = self._sv.signal_region and self._sv.signal_region:translated(location)
	local water_components, waterfall_components = self:_get_water(self._trans_region)
   local changes = {}

   for _, check in ipairs({'water_exists', 'water_volume', 'water_surface_level'}) do
      if self:has_monitor_type(check) then
         local check_changed = self['set_'..check](self, water_components)
         if check_changed then
            changes[check] = {value = self['get_'..check](self)}
         end
      end
   end

   for _, check in ipairs({'waterfall_exists', 'waterfall_volume'}) do
      if self:has_monitor_type(check) then
         local check_changed = self['set_'..check](self, waterfall_components)
         if check_changed then
            changes[check] = {value = self['get_'..check](self)}
         end
      end
   end
   
   if next(changes) then
      self.__saved_variables:mark_changed()
      if self._change_cb then
         self._change_cb(changes)
      end
      return changes
   end
end

function WaterSignal:_get_water(region)
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

return WaterSignal