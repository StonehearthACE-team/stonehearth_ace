local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_signal')

local WaterSignalComponent = class()

function WaterSignalComponent:initialize()
	self._json = radiant.entities.get_json(self)
	self._sv.signals = {}
   self._sv.is_urgent = self._json and self._json.is_urgent or false
end

function WaterSignalComponent:create()
	self._is_create = true
end

function WaterSignalComponent:restore()
   -- backwards compatibility
   if self._sv.signal_region or self._sv.monitor_types then
      self._sv.signal_region = nil
      self._sv.monitor_types = nil
      self._is_create = true
   end
end

function WaterSignalComponent:post_activate()
   if self._is_create then
      local signals = (self._json and self._json.signals) or {}
      for name, data in pairs(signals) do
         self:set_signal(name, data.region, data.monitor_types)
      end
   end
	self:_startup()
end

function WaterSignalComponent:destroy()
	self:_shutdown()
end

function WaterSignalComponent:_startup()
   stonehearth_ace.water_signal:register_water_signal(self, self._sv.is_urgent, self._is_create)
   self._is_create = nil
end

function WaterSignalComponent:_shutdown()
	stonehearth_ace.water_signal:unregister_water_signal(self)
end

function WaterSignalComponent:get_entity_id()
	return self._entity:get_id()
end

function WaterSignalComponent:set_signal(name, region, monitor_types, change_callback)
   if not region then
      local component = self._entity:get_component('region_collision_shape')
      if component then
         region = component:get_region():get()
      else
         region = Region3(Cube3(Point3.zero)) --", Point3.one" is essentially automatically added by the Cube3 constructor
      end
   end

   if not monitor_types then
      monitor_types = stonehearth.constants.water_signal.MONITOR_TYPES
   end

   local signal = self:get_signal(name)
   if signal then
      signal:set_signal_region(region)
      signal:set_monitor_types(monitor_types)
      signal:set_change_callback(change_callback)
   else
      signal = radiant.create_controller('stonehearth_ace:water_signal', self._entity, region, monitor_types, change_callback)
      self._sv.signals[name] = signal
      self.__saved_variables:mark_changed()
   end

   return signal
end

function WaterSignalComponent:get_signal(name)
   return self._sv.signals[name]
end

function WaterSignalComponent:remove_signal(name)
   if self._sv.signals[name] then
      self._sv.signals[name]:destroy()
      self._sv.signals[name] = nil
      self.__saved_variables:mark_changed()
   end
end

function WaterSignalComponent:clear_signals()
   for name, signal in pairs(self._sv.signals) do
      signal:destroy()
      self._sv.signals[name] = nil
   end
   self.__saved_variables:mark_changed()
end

function WaterSignalComponent:set_urgency(is_urgent)
	if is_urgent ~= self._sv.is_urgent then
		self._sv.is_urgent = is_urgent
		self:_shutdown()
		self:_startup()
	end
end

function WaterSignalComponent:_on_tick_water_signal()
   local changes = {}
   for name, signal in pairs(self._sv.signals) do
      changes[name] = signal:_on_tick_water_signal()
   end
   
   if next(changes) then
      radiant.events.trigger(self._entity, 'stonehearth_ace:water_signal:water_signal_changed', changes)
   end
end

return WaterSignalComponent