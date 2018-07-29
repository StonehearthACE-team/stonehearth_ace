local JobComponent = require 'stonehearth.components.job.job_component'

local AceJobComponent = class()

AceJobComponent._old_activate = JobComponent.activate
function AceJobComponent:activate(value, add_curiosity_addition)
	self:_old_activate(value, add_curiosity_addition)

	self._training_performed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:training_performed', self, self._on_training_performed)
end

AceJobComponent._old_destroy = JobComponent.destroy
function AceJobComponent:destroy(value, add_curiosity_addition)
	self:_old_destroy(value, add_curiosity_addition)

	if self._training_performed_listener then
		self._training_performed_listener:destroy()
		self._training_performed_listener = nil
	end
end

AceJobComponent._old_add_exp = JobComponent.add_exp
function AceJobComponent:add_exp(value, add_curiosity_addition)
	self:_old_add_exp(value, add_curiosity_addition)

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_add_exp', { value = value, add_curiosity_addition = add_curiosity_addition })
end

AceJobComponent._old_level_up = JobComponent.level_up
function AceJobComponent:level_up(skip_visual_effects)
	self:_old_level_up(skip_visual_effects)

	-- remove the training toggle command if we reach max level
	if self:is_combat_job() and self:is_max_level() then
		self:_remove_training_toggle()
	end

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_level_up', { skip_visual_effects = skip_visual_effects })
end

AceJobComponent._old__on_job_json_changed = JobComponent._on_job_json_changed
function AceJobComponent:_on_job_json_changed()
	self:_old__on_job_json_changed()

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_job_json_changed')
end

AceJobComponent._old_promote_to = JobComponent.promote_to
function AceJobComponent:promote_to(job_uri, options)
	self:_old_promote_to(job_uri, options)

	-- add the training toggle command if not max level
	if self:is_combat_job() and not self:is_max_level() then
		self:_add_training_toggle()
	end

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_promote', { job_uri = job_uri, options = options })
end

AceJobComponent._old_demote = JobComponent.demote
function AceJobComponent:demote(old_job_json, dont_drop_talisman)
	self:_old_demote(old_job_json, dont_drop_talisman)

	-- remove the training toggle command if it exists
	if self:is_combat_job() then
		self:_remove_training_toggle()
	end

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_demote', { old_job_json = old_job_json, dont_drop_talisman = dont_drop_talisman })
end

function AceJobComponent:is_combat_job()
	local job_info = self:get_job_info()
	return job_info and job_info:is_combat_job()
end

function AceJobComponent:get_training_enabled()
	if self:is_combat_job() then
		return radiant.entities.get_attribute(self._entity, 'stonehearth_ace:training_enabled', 1) == 1
	else
		return nil
	end
end

function AceJobComponent:set_training_enabled(enabled)
	if self:is_combat_job() then
		local prev_enabled = self:get_training_enabled()
		radiant.entities.set_attribute(self._entity, 'stonehearth_ace:training_enabled', enabled and 1 or 0)
		if prev_enabled ~= enabled then
			radiant.events.trigger(self._entity, 'stonehearth_ace:training_enabled_changed', enabled)
		end
	end
end

function AceJobComponent:toggle_training(enabled)
	if self:is_combat_job() then
		self:set_training_enabled(enabled)
		self:_add_training_toggle(enabled)
	end
end

function AceJobComponent:_get_enable_command()
	return 'stonehearth_ace:commands:toggle_training_on'
end

function AceJobComponent:_get_disable_command()
	return 'stonehearth_ace:commands:toggle_training_off'
end

function AceJobComponent:_add_training_toggle(enabled)
	if enabled == nil then
		enabled = self:get_training_enabled()
	end

	-- adjust commands accordingly
	local commands_component = self._entity:add_component('stonehearth:commands')
	self:_remove_training_toggle(commands_component)
	
	if enabled then
		local disable = self:_get_disable_command()
		if not commands_component:has_command(disable) then
			commands_component:add_command(disable)
		end
	else
		local enable = self:_get_enable_command()
		if not commands_component:has_command(enable) then
			commands_component:add_command(enable)
		end
	end
end

function AceJobComponent:_remove_training_toggle(commands_component)
	local enable = self:_get_enable_command()
	local disable = self:_get_disable_command()
	
	-- remove commands
	if not commands_component then
		commands_component = self._entity:add_component('stonehearth:commands')
	end

	if commands_component:has_command(disable) then
		commands_component:remove_command(disable)
	end
	if commands_component:has_command(enable) then
		commands_component:remove_command(enable)
	end
end

function AceJobComponent:_on_training_performed()
   local job = self:get_curr_job_controller()
   local exp = job._xp_rewards['training']
   if exp then
      self:add_exp(exp)
   end
end

return AceJobComponent