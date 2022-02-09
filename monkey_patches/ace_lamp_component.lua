local LampComponent = require 'stonehearth.components.lamp.lamp_component'
local AceLampComponent = class()
local Point3 = _radiant.csg.Point3

local ALWAYS_ON_COMMAND_URI = 'stonehearth_ace:commands:light_policy:always_on'
local WHEN_DARK_COMMAND_URI = 'stonehearth_ace:commands:light_policy:when_dark'
local NEVER_COMMAND_URI = 'stonehearth_ace:commands:light_policy:never'
local WHEN_COLD_OR_DARK_COMMAND_URI = 'stonehearth_ace:commands:light_policy:when_cold_or_dark'
local WHEN_COLD_COMMAND_URI = 'stonehearth_ace:commands:light_policy:when_cold'

function AceLampComponent:_load_json()
   local json = radiant.entities.get_json(self)  
	self._sv.buff_source = json.buff_source or false
	
   if self._sv.buff_source then
	   self._sv.buff = json.buff or 'stonehearth_ace:buffs:weather:warmth_source'
   end

   if not self._sv.light_policy then
      self._sv.light_policy = json.light_policy or 'when_dark'
   end

   if not self._sv._added_commands and not json.restrict_policy_changing then
      self:_create_commands()
   end

   self._sv.light_effect = json.light_effect

   local light_origin = json.light_origin
   if light_origin then
      self._sv.light_origin = Point3(light_origin.x, light_origin.y, light_origin.z)
   else
      self._sv.light_origin = Point3.zero
   end

   self._sv.light_radius = json.light_radius or stonehearth.constants.darkness.DEFAULT_LIGHT_RADIUS
end

function AceLampComponent:post_activate()
   self:_check_light()
end

function AceLampComponent:_create_commands()
   self._sv._added_commands = true
   local commands_component = self._entity:add_component('stonehearth:commands')
   commands_component:add_command(ALWAYS_ON_COMMAND_URI)
   commands_component:add_command(WHEN_DARK_COMMAND_URI)
   commands_component:add_command(NEVER_COMMAND_URI)
   if self._sv.buff_source and self._sv.buff == 'stonehearth_ace:buffs:weather:warmth_source' then
      commands_component:add_command(WHEN_COLD_OR_DARK_COMMAND_URI)
      commands_component:add_command(WHEN_COLD_COMMAND_URI)
   end
end

function AceLampComponent:set_light_policy(light_policy)
   self._sv.light_policy = light_policy
   self.__saved_variables:mark_changed()
   self:_check_light()
end

function AceLampComponent:get_light_policy()
   return self._sv.light_policy
end

function AceLampComponent:_create_nighttime_alarms()
   -- if the timers already exist, leave them be
   if self._sunrise_listener and self._sunset_listener then
      return
   end

   self:_destroy_nighttime_alarms()

   local calendar_constants = stonehearth.calendar:get_constants()
   local event_times = calendar_constants.event_times
   local jitter = '+20m'
   local sunrise_alarm_time = stonehearth.calendar:format_time(event_times.sunrise_start) .. jitter
   local sunset_alarm_time = stonehearth.calendar:format_time(event_times.sunset_end) .. jitter

   self._sunrise_listener = stonehearth.calendar:set_alarm(sunrise_alarm_time, function()
         self:_check_light(true)
      end)
   self._sunset_listener = stonehearth.calendar:set_alarm(sunset_alarm_time, function()
         self:_check_light()
      end)
end

function AceLampComponent:_check_light(is_sunrise)
   local should_light = false

   if self._sv.light_policy == "always_on" then
      should_light = true
      self:_destroy_nighttime_alarms()
   elseif self._sv.light_policy == "manual" then
      should_light = self._sv.is_lit
      self:_create_nighttime_alarms()
   elseif self._sv.light_policy == "when_cold" then
      should_light = stonehearth.weather:is_cold_weather()
      self:_create_nighttime_alarms()
   elseif self._sv.light_policy == "when_cold_or_dark" then
      should_light = not (is_sunrise or stonehearth.calendar:is_daytime()) or stonehearth.weather:is_dark_during_daytime() or stonehearth.weather:is_cold_weather()
      self:_create_nighttime_alarms()
   elseif self._sv.light_policy == "never" then
      self:_destroy_nighttime_alarms()
   else
      assert(self._sv.light_policy == 'when_dark')
      should_light = not (is_sunrise or stonehearth.calendar:is_daytime()) or stonehearth.weather:is_dark_during_daytime()
      self:_create_nighttime_alarms()
   end

   if should_light then
      self:light_on()
   else
      self:light_off()
   end
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

function AceLampComponent:_destroy_nighttime_alarms()
   if self._sunset_listener then
      self._sunset_listener:destroy()
      self._sunset_listener = nil
   end

   if self._sunrise_listener then
      self._sunrise_listener:destroy()
      self._sunrise_listener = nil
   end
end

return AceLampComponent