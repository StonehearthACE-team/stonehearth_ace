local Entity = _radiant.om.Entity

local get_entities_in_region = radiant.terrain.get_entities_in_region
local get_world_grid_location = radiant.entities.get_world_grid_location
local log = radiant.log.create_logger('water_signal')

local WaterSignal = class()

local WATER_MONITOR_TYPES = {
   'water_exists',
   'water_volume',
   'water_surface_level'
}
local WATERFALL_MONITOR_TYPES = {
   'waterfall_exists',
   'waterfall_volume'
}

function WaterSignal:initialize()
   self._sv._signal_region = nil
   self._sv._world_signal_region = nil
   self._sv._monitor_types = {}
   self._location = nil
   self._change_cb = nil
   self._cached_waters = {}
   self._cached_waterfalls = {}
end

function WaterSignal:create(entity_id, id, signal_region, monitor_types, change_callback)
   self._sv.id = id
   self._sv.entity_id = entity_id
   self._on_activate = function() self:set_settings(signal_region, monitor_types, change_callback) end
end

function WaterSignal:activate()
   if radiant.util.is_a(self._sv.entity_id, Entity) then
      self._sv.entity_id = self._sv.entity_id:get_id()
      self.__saved_variables:mark_changed()
      --log:debug('fixed water signal id to %s: %s', self._sv.entity_id, self:get_entity_id())
   end
   if self._on_activate then
      self._on_activate(self)
      self._on_activate = nil
   else
      stonehearth_ace.water_signal:register_water_signal(self)
   end
end

function WaterSignal:destroy()
   stonehearth_ace.water_signal:unregister_water_signal(self)
end

function WaterSignal:_reset()
   self._sv.water_exists = nil
	self._sv.water_volume = nil
	self._sv.waterfall_exists = nil
   self._sv.waterfall_volume = nil
   self._sv.water_surface_level = nil
	self.__saved_variables:mark_changed()
end

function WaterSignal:set_settings(signal_region, monitor_types, change_callback)
   self:add_monitor_types(monitor_types, true)
   self:set_change_callback(change_callback)
   self:set_signal_region(signal_region)

   self:_on_tick_water_signal()
end

function WaterSignal:get_id()
   return self._sv.id
end

function WaterSignal:get_entity_id()
	return self._sv.entity_id
end

function WaterSignal:get_signal_region()
   return self._sv._signal_region
end

function WaterSignal:get_world_signal_region()
   return self._sv._world_signal_region
end

function WaterSignal:set_signal_region(signal_region)
   self._sv._signal_region = signal_region
   self:_update_region()
end

function WaterSignal:set_location(location)
   if self._location ~= location then
      self._location = location
      self:_update_region()
   end
end

function WaterSignal:_update_region()
   local changed = false
   local region
   if self._sv._signal_region and self._location then
      region = self._sv._signal_region:translated(self._location)
      changed = true
   elseif self._sv._world_signal_region then
      changed = true
   end

   if changed then
      self._sv._world_signal_region = region
      stonehearth_ace.water_signal:register_water_signal(self)
      self:_on_tick_water_signal()
   end
   self.__saved_variables:mark_changed()
end

function WaterSignal:has_monitor_type(monitor_type)
   return self._sv._monitor_types[monitor_type] ~= nil
end

function WaterSignal:monitors_water()
   for _, type in ipairs(WATER_MONITOR_TYPES) do
      if self._sv._monitor_types[type] then
         return true
      end
   end
   return false
end

function WaterSignal:monitors_waterfall()
   for _, type in ipairs(WATERFALL_MONITOR_TYPES) do
      if self._sv._monitor_types[type] then
         return true
      end
   end
   return false
end

function WaterSignal:get_monitor_types()
   return radiant.shallow_copy(self._sv._monitor_types)
end

function WaterSignal:set_monitor_types(monitor_types, skip_register)
   local changed = false
   local types = {}
   for _, monitor_type in ipairs(monitor_types) do
      types[monitor_type] = true
      if not self._sv._monitor_types[monitor_type] then
         changed = true
         self._sv._monitor_types[monitor_type] = true
      end
   end
   for monitor_type, _ in pairs(self._sv._monitor_types) do
      if not types[monitor_type] then
         changed = true
         self._sv._monitor_types[monitor_type] = nil
      end
   end

   if changed then
      self:_reset()
   end
   if not skip_register then
      stonehearth_ace.water_signal:register_water_signal(self)
   end
end

-- should these be filtered on stonehearth.constants.water_signal.MONITOR_TYPES?
function WaterSignal:add_monitor_types(monitor_types, skip_register)
   local changed = false
   for _, monitor_type in ipairs(monitor_types) do
      if not self._sv._monitor_types[monitor_type] then
         changed = true
         self._sv._monitor_types[monitor_type] = true
      end
   end

   if changed then
      self:_reset()
   end
   if not skip_register then
      stonehearth_ace.water_signal:register_water_signal(self)
   end
end

function WaterSignal:remove_monitor_types(monitor_types, skip_register)
   local changed = false
   if monitor_types then
      for _, monitor_type in ipairs(monitor_types) do
         if self._sv._monitor_types[monitor_type] then
            changed = true
            self._sv._monitor_types[monitor_type] = nil
         end
      end
   elseif next(self._sv._monitor_types) then
      -- if we passed in nil, clear out the whole thing
      changed = true
      self._sv._monitor_types = {}
   end

	if changed then
      self:_reset()
   end
   if not skip_register then
      stonehearth_ace.water_signal:register_water_signal(self)
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
	for id, w in pairs(water_components) do
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
   local volume_info = water_comp:get_volume_info()
   local base_intersection = self._sv._world_signal_region:intersect_region(volume_info.base_region)
   local top_intersection = self._sv._world_signal_region:intersect_region(volume_info.top_region)
   local volume = base_intersection:get_area() + top_intersection:get_area() * volume_info.top_height
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
   for id, w in pairs(water_components) do
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
	for id, w in pairs(waterfall_components) do
		volume = volume + w:get_volume()
	end

	local prev_volume = self._sv.waterfall_volume
	self._sv.waterfall_volume = volume

	if volume ~= prev_volume then
      return true
   end
   return false
end

function WaterSignal:_on_tick_water_signal(waters, waterfalls)
	if not self._sv._signal_region or not next(self._sv._monitor_types) then
		return
	end
	
	-- do we really need to update the water regions we're checking every single tick?
	-- not sure how expensive this is
	local region = self._sv._world_signal_region
	if not region then
		self:_reset()
		return
	end
   
	local water_components, waterfall_components = self:_get_water(region, waters, waterfalls)
   local changes = {}

   for _, check in ipairs(WATER_MONITOR_TYPES) do
      if self._sv._monitor_types[check] then
         local check_changed = self['set_'..check](self, water_components)
         if check_changed then
            changes[check] = {value = self['get_'..check](self)}
         end
      end
   end

   for _, check in ipairs(WATERFALL_MONITOR_TYPES) do
      if self._sv._monitor_types[check] then
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

function WaterSignal:_get_water(region, waters, waterfalls)
	if not region then
		return {}, {}
   end
   
   if waters or waterfalls then
      for id, intersected in pairs(waters or {}) do
         if intersected then
            if not self._cached_waters[id] then
               local entity = radiant.entities.get_entity(id)
               if entity and entity:is_valid() then
                  self._cached_waters[id] = entity:get_component('stonehearth:water')
               end
            end
         else
            self._cached_waters[id] = nil
         end
      end
      for id, intersected in pairs(waterfalls or {}) do
         if intersected then
            if not self._cached_waterfalls[id] then
               local entity = radiant.entities.get_entity(id)
               if entity and entity:is_valid() then
                  self._cached_waterfalls[id] = entity:get_component('stonehearth:waterfall')
               end
            end
         else
            self._cached_waterfalls[id] = nil
         end
      end
   else
      local entities = get_entities_in_region(region)
      local check_water = self:monitors_water()
      local check_waterfall = self:monitors_waterfall()

      self._cached_waters = {}
      self._cached_waterfalls = {}

      for id, e in pairs(entities) do
         if check_water then
            local water_component = e:get_component('stonehearth:water')
            if water_component then
               self._cached_waters[id] = water_component
            end
         end

         if check_waterfall then
            local waterfall_component = e:get_component('stonehearth:waterfall')
            if waterfall_component then
               self._cached_waterfalls[id] = waterfall_component
            end
         end
      end
   end

	return self._cached_waters, self._cached_waterfalls
end

return WaterSignal