local log = radiant.log.create_logger('toggle_enabled')

local ToggleEnabledComponent = class()

function ToggleEnabledComponent:create()
	local json = radiant.entities.get_json(self)
	self._sv.enabled = false or json.enabled
	self._sv.on_command = json.on_command or 'stonehearth_ace:commands:toggle_enabled_on'
	self._sv.off_command = json.off_command or 'stonehearth_ace:commands:toggle_enabled_off'
	self._sv.alert_on_reload = false or json.alert_on_reload
	self.__saved_variables:mark_changed()
end

function ToggleEnabledComponent:restore()
	self._is_restore = true
end

function ToggleEnabledComponent:post_activate()
	if self._sv.alert_on_reload then
		self:_set_enabled(self._sv.enabled)
	else
		self:_on_enabled_changed()
	end
end

function ToggleEnabledComponent:_on_enabled_changed()
	-- swap commands
	local commands_component = self._entity:get_component('stonehearth:commands')
	if commands_component then
		if self._sv.enabled then
			commands_component:remove_command(self._sv.on_command)
			if not commands_component:has_command(self._sv.off_command) then
				commands_component:add_command(self._sv.off_command)
			end
		else
			commands_component:remove_command(self._sv.off_command)
			if not commands_component:has_command(self._sv.on_command) then
				commands_component:add_command(self._sv.on_command)
			end
		end
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

return ToggleEnabledComponent
