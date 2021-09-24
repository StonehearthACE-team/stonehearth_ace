local LampComponent = require 'stonehearth.components.lamp.lamp_component'
local AceLampComponent = class()

AceLampComponent._ace_old__load_json = LampComponent._load_json
function AceLampComponent:_load_json()
   local json = radiant.entities.get_json(self)  
	self._sv.buff_source = json.buff_source or false
	
   if self._sv.buff_source then
	   self._sv.buff = json.buff or 'stonehearth_ace:buffs:weather:warmth_source'
   end
	
	self:_ace_old__load_json()
end

function AceLampComponent:_create_nighttime_alarms()
   local calendar_constants = stonehearth.calendar:get_constants()
   local event_times = calendar_constants.event_times
   local jitter = '+20m'
   local sunrise_alarm_time = stonehearth.calendar:format_time(event_times.sunrise_start) .. jitter
   local sunset_alarm_time = stonehearth.calendar:format_time(event_times.sunset_end) .. jitter

   self._sunrise_listener = stonehearth.calendar:set_alarm(sunrise_alarm_time, function()
         self:light_off()
      end)
   self._sunset_listener = stonehearth.calendar:set_alarm(sunset_alarm_time, function()
         self:light_on()
      end)
end

function AceLampComponent:light_on()
   self._sv.is_lit = true

   self._render_info:set_model_variant('lamp_on')

   if self._sv.light_effect and not self._running_effect then
      self._running_effect = radiant.effects.run_effect(self._entity, self._sv.light_effect);
   end
	
	if self._sv.buff_source and not radiant.entities.has_buff(self._entity, self._sv.buff) then
		radiant.entities.add_buff(self._entity, self._sv.buff)
	end

   self.__saved_variables:mark_changed()
end

function AceLampComponent:light_off()
   self._sv.is_lit = false

   self._render_info:set_model_variant('')

   if self._running_effect then
      self._running_effect:stop()
      self._running_effect = nil
   end
	
	if self._sv.buff_source then
		radiant.entities.remove_buff(self._entity, self._sv.buff)
	end

   self.__saved_variables:mark_changed()
end

return AceLampComponent