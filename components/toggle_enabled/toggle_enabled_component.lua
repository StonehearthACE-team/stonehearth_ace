local log = radiant.log.create_logger('toggle_enabled')

local ToggleEnabledComponent = class()

function ToggleEnabledComponent:create()
	local json = radiant.entities.get_json(self)
	self._sv.enabled = false or json.enabled
	self._sv.enable_command = json.enable_command or 'stonehearth_ace:commands:toggle_enabled_on'
	self._sv.disable_command = json.disable_command or 'stonehearth_ace:commands:toggle_enabled_off'
	self._sv.enable_effect_name = json.enable_effect
	self._sv.disable_effect_name = json.disable_effect
	self._sv.alert_on_reload = false or json.alert_on_reload
	self.__saved_variables:mark_changed()
end

function ToggleEnabledComponent:restore()
	self._is_restore = true
end

function ToggleEnabledComponent:post_activate()
	if self._is_restore and self._sv.alert_on_reload then
		self:_set_enabled(self._sv.enabled)
	else
		self:_on_enabled_changed()
	end
end

function ToggleEnabledComponent:destroy()
	if self._disable_effect then
		self._disable_effect:stop()
		self._disable_effect = nil
	end
	if self._enable_effect then
		self._enable_effect:stop()
		self._enable_effect = nil
	end
end

function ToggleEnabledComponent:_on_enabled_changed()
	-- swap commands
	local commands_component = self._entity:get_component('stonehearth:commands')
	if commands_component then
		if self._sv.enabled then
			commands_component:remove_command(self._sv.enable_command)
			if not commands_component:has_command(self._sv.disable_command) then
				commands_component:add_command(self._sv.disable_command)
			end
		else
			commands_component:remove_command(self._sv.disable_command)
			if not commands_component:has_command(self._sv.enable_command) then
				commands_component:add_command(self._sv.enable_command)
			end
		end
	end

	if self._sv.enabled then
		self:_run_enable_effect()
	else
		self:_run_disable_effect()
	end
end

function ToggleEnabledComponent:get_enabled()
	return self._sv.enabled
end

function ToggleEnabledComponent:set_enabled(value)
	if self._sv.enabled ~= value then
		self:_set_enabled(value)
	end
end

function ToggleEnabledComponent:_set_enabled(value)
	self._sv.enabled = value
	self.__saved_variables:mark_changed()

	self:_on_enabled_changed()

	radiant.events.trigger(self._entity, 'stonehearth_ace:enabled_changed', value)
end

function ToggleEnabledComponent:_run_enable_effect()
   if self._disable_effect then
      self._disable_effect:stop()
      self._disable_effect = nil
   end
   if self._sv.enable_effect_name and not self._enable_effect then
      self._enable_effect = radiant.effects.run_effect(self._entity, self._sv.enable_effect_name)
         :set_cleanup_on_finish(false)
   end
end

function ToggleEnabledComponent:_run_disable_effect()
   if self._enable_effect then
      self._enable_effect:stop()
      self._enable_effect = nil
   end
   if self._sv.disable_effect_name and not self._disable_effect then
      self._disable_effect = radiant.effects.run_effect(self._entity, self._sv.disable_effect_name)
         :set_cleanup_on_finish(false)
   end
end

return ToggleEnabledComponent
