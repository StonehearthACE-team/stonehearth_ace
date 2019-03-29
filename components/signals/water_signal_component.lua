local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_signal')

local WaterSignalComponent = class()

function WaterSignalComponent:initialize()
   self._sv._signals = {}
end

function WaterSignalComponent:activate()
   if self._sv._is_mobile == nil then
      local json = radiant.entities.get_json(self)
      self._sv._is_mobile = json and json.is_mobile or false
   end
   
   for name, signal in pairs(self._sv._signals) do
      if not signal:get_id() then
         signal:destroy()
         self._sv._signals[name] = nil
         self.__saved_variables:mark_changed()
      end
   end

   self._added_to_world_trace = self._entity:add_component('mob'):trace_parent('water signal entity added or removed') --, _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
         self:_location_changed()
      end)

   self:_setup_location_trace()
end

function WaterSignalComponent:set_is_mobile(is_mobile)
   self._sv._is_mobile = is_mobile or false
   self.__saved_variables:mark_changed()
   self:_setup_location_trace()
end

function WaterSignalComponent:_setup_location_trace()
   self:_destroy_location_trace()
   
   if self._sv._is_mobile then
      self._location_trace = stonehearth.calendar:set_interval('water signal mobility check', '9m+2m', function()
         self:_location_changed()
      end)
   else
      self._location_trace = self._entity:add_component('mob'):trace_transform('water signal entity moved') --, _radiant.dm.TraceCategories.SYNC_TRACE)
         :on_changed(function()
            self:_location_changed()
         end)
   end
   self:_location_changed()
end

function WaterSignalComponent:destroy()
   if self._added_to_world_trace then
      self._added_to_world_trace:destroy()
      self._added_to_world_trace = nil
   end

   self:_destroy_location_trace()

   self:clear_signals()
end

function WaterSignalComponent:_destroy_location_trace()
   if self._location_trace then
      self._location_trace:destroy()
      self._location_trace = nil
   end
end

function WaterSignalComponent:_location_changed()
   local location = radiant.entities.get_world_grid_location(self._entity)
   --log:debug('entity %s location trace: %s', self._entity, location or 'NIL')
   if location ~= self._location then
      self._location = location
      for _, signal in pairs(self._sv._signals) do
         signal:set_location(location)
      end
   end
end

function WaterSignalComponent:get_entity_id()
	return self._entity:get_id()
end

function WaterSignalComponent:set_signal(name, region, monitor_types, change_callback)
   local region_extrusion = {}
   if radiant.util.is_a(region, 'table') then
      region_extrusion = region
      region = nil
   end
   
   if not region then
      local component = self._entity:get_component('region_collision_shape')
      if component then
         region = component:get_region():get()
      else
         -- this is important for crops that have no region_collision_shape
         region = Region3(Cube3(Point3.zero)) --", Point3.one" is essentially automatically added by the Cube3 constructor
      end

      for dir, extrusion in pairs(region_extrusion) do
         region = region:extruded(dir, extrusion[1] or 0, extrusion[2] or 0)
      end
   end

   if not monitor_types then
      monitor_types = stonehearth.constants.water_signal.MONITOR_TYPES
   end

   local signal = self:get_signal(name)
   if signal then
      signal:set_settings(region, monitor_types, change_callback)
   else
      signal = radiant.create_controller('stonehearth_ace:water_signal', self:get_entity_id(), self:get_entity_id() .. '|' .. name, region, monitor_types, change_callback)
      self._sv._signals[name] = signal
      self.__saved_variables:mark_changed()
   end
   signal:set_location(self._location)

   return signal
end

function WaterSignalComponent:has_signal(name)
   if name then
      return self._sv._signals[name] ~= nil
   end
   return next(self._sv._signals) ~= nil
end

function WaterSignalComponent:get_signals()
   return self._sv._signals
end

function WaterSignalComponent:get_signal(name)
   return self._sv._signals[name]
end

function WaterSignalComponent:remove_signal(name)
   if self._sv._signals[name] then
      self._sv._signals[name]:destroy()
      self._sv._signals[name] = nil
      self.__saved_variables:mark_changed()
   end
end

function WaterSignalComponent:clear_signals()
   for name, signal in pairs(self._sv._signals) do
      signal:destroy()
      self._sv._signals[name] = nil
   end
   self.__saved_variables:mark_changed()
end

return WaterSignalComponent