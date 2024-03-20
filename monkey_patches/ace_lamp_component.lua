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
   if not json then
      return
   end

	self._sv.buff_source = json.buff_source or false
	local appropriate_policy = 'when_dark'

   if self._sv.buff_source then
	   self._sv.buff = json.buff or 'stonehearth_ace:buffs:weather:warmth_source'
      if self._sv.buff == 'stonehearth_ace:buffs:weather:warmth_source' then
         appropriate_policy = 'when_cold_or_dark'
      end
   end

   if not self._sv.light_policy then
      self._sv.light_policy = json.light_policy or appropriate_policy
   end

   if not self._sv._added_commands and not self._entity:get_component('stonehearth:firepit') and
         (json.force_policy_changing or not json.restrict_policy_changing) then
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
   self:_create_parent_listener()
end

AceLampComponent._ace_old_destroy = LampComponent.__user_destroy
function AceLampComponent:destroy()
   self:_destroy_parent_listener()
   self:_destroy_parent_light_listener()
   self:_ace_old_destroy()
end

function AceLampComponent:_destroy_parent_listener()
   if self._parent_listener then
      self._parent_listener:destroy()
      self._parent_listener = nil
   end
end

function AceLampComponent:_destroy_parent_light_listener()
   if self._parent_light_listener then
      self._parent_light_listener:destroy()
      self._parent_light_listener = nil
   end
end

function AceLampComponent:_create_parent_listener()
   if not self._parent_listener then
      self._parent_listener = self._entity:get_component('mob'):trace_parent('lamp added or removed')
         :on_changed(function(parent_entity)
               if not parent_entity then
                  self:_destroy_parent_light_listener()
               else
                  self:_create_parent_light_listener(parent_entity)
               end
            end)
         :push_object_state()
   end
end

function AceLampComponent:_create_parent_light_listener(parent)
   self:_destroy_parent_light_listener()

   self._parent_light_listener = radiant.events.listen(parent, 'stonehearth_ace:lamp:light_changed', function()
         self:_on_parent_light_changed(parent)
      end)
   self:_on_parent_light_changed(parent)
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

   if self._sv.light_policy == "parent" then
      self:_destroy_nighttime_alarms()
      return
   elseif self._sv.light_policy == "always_on" then
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

function AceLampComponent:_on_parent_light_changed(parent)
   local lamp_component = parent and parent:get_component('stonehearth:lamp')
   if lamp_component then
      if lamp_component:is_lit() then
         self:light_on()
      else
         self:light_off()
      end
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

   radiant.events.trigger_async(self._entity, 'stonehearth_ace:lamp:light_changed')

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

   radiant.events.trigger_async(self._entity, 'stonehearth_ace:lamp:light_changed')

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