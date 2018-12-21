local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_signal')

local WaterSignalComponent = class()

function WaterSignalComponent:initialize()
	self._sv.signals = {}
end

function WaterSignalComponent:activate()
   for name, signal in pairs(self._sv.signals) do
      if not signal:get_id() then
         signal:destroy()
         self._sv.signals[name] = nil
         self.__saved_variables:mark_changed()
      end
   end

   self._location_trace = self._entity:add_component('mob'):trace_transform('water signal entity moved', _radiant.dm.TraceCategories.SYNC_TRACE)
      :on_changed(function()
         local location = radiant.entities.get_world_grid_location(self._entity)
         if location ~= self._location then
            self._location = location
            for _, signal in pairs(self._sv.signals) do
               signal:set_location(location)
            end
         end
      end)
      :push_object_state()
end

function WaterSignalComponent:destroy()
   if self._location_trace then
      self._location_trace:destroy()
      self._location_trace = nil
   end
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
         -- this is important for crops that have no region_collision_shape
         region = Region3(Cube3(Point3.zero)) --", Point3.one" is essentially automatically added by the Cube3 constructor
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
      self._sv.signals[name] = signal
      self.__saved_variables:mark_changed()
   end
   signal:set_location(self._location)

   return signal
end

function WaterSignalComponent:get_signals()
   return self._sv.signals
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

return WaterSignalComponent