local JobComponent = require 'stonehearth.components.job.job_component'

local AceJobComponent = class()

AceJobComponent._ace_old_activate = JobComponent.activate
function AceJobComponent:activate(value, add_curiosity_addition)
	self:_ace_old_activate(value, add_curiosity_addition)

	self._max_level_from_training = 3
	self._training_performed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:training_performed', self, self._on_training_performed)
end

AceJobComponent._ace_old_destroy = JobComponent.destroy
function AceJobComponent:destroy(value, add_curiosity_addition)
	self:_ace_old_destroy(value, add_curiosity_addition)

	if self._training_performed_listener then
		self._training_performed_listener:destroy()
		self._training_performed_listener = nil
	end
end

function AceJobComponent:add_exp(value, add_curiosity_addition, options)
   -- if we weren't being given any exp, who cares?
   if not value or value <= 0 then
      return
   end
   
   if not self:can_level_up() then
      return
   end

   if stonehearth.player:is_npc(self._entity) then
      -- no exp for npc players
      return
   end

   if options and options.only_through_level and options.only_through_level < self._sv.curr_job_level then
      return
   end

   local attributes_component = self._entity:get_component('stonehearth:attributes')
   local xp_multiplier = attributes_component and attributes_component:get_attribute('xp_multiplier')
   value = value * xp_multiplier

   -- Add a curiosity exp addition
   -- TODO: this should really be percentage based instead of a constant value
   -- otherwise, jobs with frequent small experience events (combat) get a huge multiplier
   local exp_mult = 1
   if add_curiosity_addition ~= false then
      if attributes_component then
         local curiosity = attributes_component:get_attribute('curiosity')
         -- we leave the multiplier the same in constants so that the crafter job can still use it in the same way
         -- because the crafter job is harder to patch/override ><
         exp_mult = 1 + curiosity * stonehearth.constants.attribute_effects.CURIOSITY_EXPERIENCE_MULTIPLER * 0.1
         if exp_mult < 1 then
            exp_mult = 1
         end
      end
   end
   -- make sure that we get at least 1 exp from this
   value = math.max(1, radiant.math.round(value * exp_mult))

   self._sv.current_level_exp = self._sv.current_level_exp + value

   if not self._sv.xp_to_next_lv then
      log:error('%s needs an xp equation in job component data', self._entity)
      return
   end

   local prevent_level_up = options and options.prevent_level_up
   if prevent_level_up or (options and options.only_through_level and options.only_through_level == self._sv.curr_job_level) then
      self._sv.current_level_exp = math.min(self._sv.current_level_exp, self._sv.xp_to_next_lv - 1)
   end

   while self._sv.current_level_exp >= self._sv.xp_to_next_lv do
      self._sv.current_level_exp = self._sv.current_level_exp - self._sv.xp_to_next_lv
      self:level_up()
   end

   self.__saved_variables:mark_changed()

   radiant.events.trigger(self._entity, 'stonehearth_ace:on_add_exp', { value = value, add_curiosity_addition = add_curiosity_addition, prevent_level_up = prevent_level_up })
end

AceJobComponent._ace_old_level_up = JobComponent.level_up
function AceJobComponent:level_up(skip_visual_effects)
	self:_ace_old_level_up(skip_visual_effects)

	-- remove the training toggle command if we reach max level
	if not self:is_trainable() then
		self:_remove_training_toggle()
	end

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_level_up', { skip_visual_effects = skip_visual_effects })
end

AceJobComponent._ace_old__on_job_json_changed = JobComponent._on_job_json_changed
function AceJobComponent:_on_job_json_changed()
	self:_ace_old__on_job_json_changed()

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_job_json_changed')
end

AceJobComponent._ace_old_promote_to = JobComponent.promote_to
function AceJobComponent:promote_to(job_uri, options)
	self:_ace_old_promote_to(job_uri, options)

	-- add the training toggle command if not max level
	if self:is_trainable() then
		self:_add_training_toggle()
   end
   
   if self:has_multiple_equipment_preferences() then
      self:_add_equipment_preferences_toggle()
   end

   self:_register_entity_types()

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_promote', { job_uri = job_uri, options = options })
end

AceJobComponent._ace_old_demote = JobComponent.demote
function AceJobComponent:demote(old_job_json, dont_drop_talisman)
	self:_ace_old_demote(old_job_json, dont_drop_talisman)

	-- remove the training toggle command if it exists
	if self:is_combat_job() then
		self:_remove_training_toggle()
   end
   
   self:_remove_equipment_preferences_toggle()

   self:_unregister_entity_types()

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_demote', { old_job_json = old_job_json, dont_drop_talisman = dont_drop_talisman })
end

function AceJobComponent:_register_entity_types()
   -- register all types we care about (this can easily be patched to support more)
   local town = stonehearth.town:get_town(self._entity)
   if town then
      if self:has_ai_pack('stonehearth:ai_pack:repairing') then
         town:register_entity_type('stonehearth_ace:can_repair', self._entity)
      end
   end
end

function AceJobComponent:_unregister_entity_types()
   local town = stonehearth.town:get_town(self._entity)
   if town then
      town:unregister_entity_types(self._entity)
   end
end

function AceJobComponent:has_multiple_equipment_preferences()
   local job_controller = self:get_curr_job_controller()
   local count = job_controller and #job_controller:get_equipment_roles()

   return count and count > 1
end

function AceJobComponent:get_all_equipment_preferences()
   local job_controller = self:get_curr_job_controller()
   local prefs = job_controller and job_controller:get_all_equipment_preferences()
end

function AceJobComponent:get_equipment_preferences()
   local job_controller = self:get_curr_job_controller()
   local prefs = job_controller and job_controller:get_equipment_preferences()

   return prefs
end

function AceJobComponent:set_next_equipment_role(from_role)
   local job_controller = self:get_curr_job_controller()
   if job_controller then
      job_controller:set_next_equipment_role(from_role)
      self:update_equipment_preferences_toggle()
      return job_controller:get_equipment_role()
   end
end

function AceJobComponent:has_ai_action(action_uri)
	local job_equipment = self:get_job_equipment()

	for _, equipment in pairs(job_equipment) do
		local equipment_piece = equipment:get_component('stonehearth:equipment_piece')
		if equipment_piece and equipment_piece:has_ai_action(action_uri) then
			return true
		end
	end

	return false
end

function AceJobComponent:has_ai_pack(pack_uri)
	local job_equipment = self:get_job_equipment()

	for _, equipment in pairs(job_equipment) do
		local equipment_piece = equipment:get_component('stonehearth:equipment_piece')
		if equipment_piece and equipment_piece:has_ai_pack(pack_uri) then
			return true
		end
	end

	return false
end

function AceJobComponent:has_ai_task_group(task_group_uri)
	local job_equipment = self:get_job_equipment()

	for _, equipment in pairs(job_equipment) do
		local equipment_piece = equipment:get_component('stonehearth:equipment_piece')
		if equipment_piece and equipment_piece:has_ai_task_group(task_group_uri) then
			return true
		end
	end

	return false
end

function AceJobComponent:is_combat_job()
	local job_info = self:get_job_info()
	return job_info and job_info:is_combat_job()
end

function AceJobComponent:is_trainable()
	return self:is_combat_job() and self:get_current_job_level() < self._max_level_from_training
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

function AceJobComponent:update_equipment_preferences_toggle()
   self:_remove_equipment_preferences_toggle()
   self:_add_equipment_preferences_toggle()
end

function AceJobComponent:_add_equipment_preferences_toggle()
   local job_controller = self:get_curr_job_controller()
   local data = job_controller and job_controller:get_equipment_preferences()
   if data then
      local commands_component = self._entity:add_component('stonehearth:commands')
      self._sv.current_equipment_preferences_command = data.command
      commands_component:add_command(data.command)

      self.__saved_variables:mark_changed()
   end
end

function AceJobComponent:_remove_equipment_preferences_toggle()
   local commands_component = self._entity:add_component('stonehearth:commands')
   if commands_component and self._sv.current_equipment_preferences_command then
      commands_component:remove_command(self._sv.current_equipment_preferences_command)
   end
end

return AceJobComponent