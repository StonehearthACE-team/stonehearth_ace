local rng = _radiant.math.get_default_rng()

local JobComponent = require 'stonehearth.components.job.job_component'

local AceJobComponent = class()

AceJobComponent._ace_old_activate = JobComponent.activate
function AceJobComponent:activate(value, add_curiosity_addition)
	self:_ace_old_activate(value, add_curiosity_addition)
   self:_update_job_index()
	self._max_level_from_training = 3
	self._training_performed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:training_performed', self, self._on_training_performed)
end

AceJobComponent._ace_old_post_activate = JobComponent.post_activate
function AceJobComponent:post_activate()
   self:_update_job_index()

   self:_ace_old_post_activate()
end

AceJobComponent._ace_old_destroy = JobComponent.__user_destroy
function AceJobComponent:destroy()
	self:_ace_old_destroy()

	if self._training_performed_listener then
		self._training_performed_listener:destroy()
		self._training_performed_listener = nil
	end
end

function AceJobComponent:get_job_equipment_uris()
   return self._sv._job_equipment_uris or {}
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

   self:_call_job('set_current_level_exp', self._sv.current_level_exp)

   self.__saved_variables:mark_changed()

   radiant.events.trigger(self._entity, 'stonehearth_ace:on_add_exp', { value = value, add_curiosity_addition = add_curiosity_addition, prevent_level_up = prevent_level_up })
end

AceJobComponent._ace_old__on_job_json_changed = JobComponent._on_job_json_changed
function AceJobComponent:_on_job_json_changed()
	self:_ace_old__on_job_json_changed()

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_job_json_changed')
end

function AceJobComponent:get_job_info()
   return stonehearth.job:get_job_info(radiant.entities.get_player_id(self._entity), self._sv.job_uri, self._sv.population_override)
end

function AceJobComponent:set_population_override(population_uri)
   self._sv.population_override =  population_uri
   self:_update_job_index()
end

function AceJobComponent:get_population_override()
   return self._sv.population_override
end

function AceJobComponent:get_current_talisman_uri()
   return self._sv.current_talisman_uri
end

function AceJobComponent:get_curr_job_name()
   return self._sv.curr_job_name
end

-- this is just for the sake of the UI, so that opening the promotion tree doesn't require requesting the job index
-- as such, we need to store it in _sv
function AceJobComponent:_update_job_index()
   local player_id = radiant.entities.get_player_id(self._entity)
   local pop = stonehearth.population:get_population(player_id)
   self._sv.job_index = pop and pop:get_job_index(self._sv.population_override)
   self.__saved_variables:mark_changed()
end

function AceJobComponent:get_job_description_path(job_uri)
   local player_id = radiant.entities.get_player_id(self._entity)
   local job_controller = stonehearth.job:get_jobs_controller(player_id)
   return job_controller:get_job_description(job_uri, self._sv.population_override)
end

function AceJobComponent:get_current_job_description_path()
   return self._sv.job_uri and self:get_job_description_path(self._sv.job_uri)
end

-- Called by add_exp. Calls the profession-specific job controller to tell it to level up
-- have to override the whole thing to add title data to the bulletin ><
function AceJobComponent:level_up(skip_visual_effects)
   --Change all the attributes to the new level
   --Should the general HP increase (class independent) be reflected as a permanent buff or a quiet stat increase?
   local attributes_component = self._entity:get_component('stonehearth:attributes')
   local curr_level = attributes_component:get_attribute('total_level')
   self._sv.total_level = curr_level + 1
   attributes_component:set_attribute('total_level', self._sv.total_level)

   --Add to the total job levels statistics
   local stats_comp = self._entity:get_component('stonehearth_ace:statistics')
   if stats_comp then
      stats_comp:set_stat('totals', 'levels', self._sv.total_level)
   end

   --Add all the universal level dependent buffs/bonuses, etc

   self:_call_job('level_up')
   local job_name = self._job_json.display_name

   local new_level = self:_call_job('get_job_level') or 1
   self._sv.curr_job_level = new_level
   local class_perk_descriptions = self:_apply_perk_for_level(new_level)
   local has_class_perks = false
   if #class_perk_descriptions > 0 then
      has_class_perks = true
   end

   self:_set_custom_description(self:_get_current_job_title(self._job_json))

   local player_id = radiant.entities.get_player_id(self._entity)
   local name = radiant.entities.get_display_name(self._entity)
   local title = self._default_level_announcement

   local has_race_perks = false
   local race_perk_descriptions = self:_add_race_perks()
   if race_perk_descriptions and #race_perk_descriptions > 0 then
      has_race_perks = true
   end

   if not skip_visual_effects then
      --post the bulletin
      local level_bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
         :set_ui_view('StonehearthLevelUpBulletinDialog')
         :set_callback_instance(self)
         :set_type('level_up')
         :set_data({
            title = title,
            char_name = name,
            zoom_to_entity = self._entity,
            has_class_perks = has_class_perks,
            class_perks = class_perk_descriptions,
            has_race_perks = has_race_perks,
            race_perks = race_perk_descriptions
         })
         :set_active_duration('1h')
         :add_i18n_data('entity_display_name', radiant.entities.get_display_name(self._entity))
         :add_i18n_data('entity_custom_name', radiant.entities.get_custom_name(self._entity))
         :add_i18n_data('entity_custom_data', radiant.entities.get_custom_data(self._entity))
         :add_i18n_data('job_name', job_name)
         :add_i18n_data('level_number', new_level)
   end

   --Trigger an event so people can extend the class system
   radiant.events.trigger_async(self._entity, 'stonehearth:level_up', {
      level = new_level,
      job_uri = self._sv.job_uri,
      job_name = self._sv.curr_job_name })

   --Inform job controllers
   if self:get_job_info() then
      self:get_job_info():promote_member(self._entity)
   end

   if not self:is_trainable() then
      self:_remove_training_toggle()
   end

   if not skip_visual_effects then
      radiant.effects.run_effect(self._entity, 'stonehearth:effects:level_up')
   end

   if new_level > 0 then
      radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:job:gained_a_level')
   end

   self._sv.xp_to_next_lv = self:_calculate_xp_to_next_lv()
   self.__saved_variables:mark_changed()
end

--AceJobComponent._ace_old_promote_to = JobComponent.promote_to
-- have to override the whole thing to add title data to the bulletin ><
function AceJobComponent:promote_to(job_uri, options)
	assert(self._sv.allowed_jobs == nil or self._sv.allowed_jobs[job_uri])

   local is_npc = stonehearth.player:is_npc(self._entity)
   local talisman_entity = options and options.talisman

   local old_job_json = self._job_json

   self._sv.job_json_path = self:get_job_description_path(job_uri)
   self._job_json = radiant.resources.load_json(self._sv.job_json_path, true)

   if self._job_json then
      self:_on_job_json_changed()
      self:demote(old_job_json, options and options.dont_drop_talisman)

      self._sv.job_uri = job_uri

      --Strangely, doesn't exist yet when this is called in init, creates duplicate component!
      local attributes_component = self._entity:get_component('stonehearth:attributes')
      self._sv.total_level = attributes_component:get_attribute('total_level')

      -- equip your abilities item
      self:_equip_abilities(self._job_json)

      -- equip your equipment, unless you're an npc, in which case the game is responsible for manually
      -- adding the proper equipment
      if not is_npc then
         self:_equip_equipment(self._job_json, talisman_entity)
      end

      self:reset_to_default_combat_stance()

      local first_time_job = false
      --Create the job controller, if we don't yet have one
      if not self._sv.job_controllers[self._sv.job_uri] then
         --create the controller
         radiant.assert(self._job_json.controller, 'no controller specified for job %s', self._sv.job_uri)
         self._sv.job_controllers[self._sv.job_uri] =
            radiant.create_controller(self._job_json.controller, self._entity)
         first_time_job = true
      end
      self._sv.curr_job_controller = self._sv.job_controllers[self._sv.job_uri]
      self:_call_job('promote', self._sv.job_json_path, {talisman = talisman_entity})

      self._sv.curr_job_level = self:_call_job('get_job_level') or 1
      self:_set_custom_description(self:_get_current_job_title(self._job_json))

      --Whenever you get a new job, dump all the xp that you've accured so far to your next level
      self._sv.xp_to_next_lv = self:_calculate_xp_to_next_lv()
      self._sv.current_level_exp = math.min(self._sv.xp_to_next_lv and (self._sv.xp_to_next_lv - 1) or 0, self:_call_job('get_current_level_exp') or 0)

      --Add all existing perks, if any
      local class_perk_descriptions = self:_apply_existing_perks()

      --The old work order configuration is no longer relevant.
      self._entity:add_component('stonehearth:work_order'):clear_work_order_statuses()
      self:_update_job_work_order()

      --Add self to task groups
      if self._job_json.task_groups then
         self:_add_to_task_groups(self._job_json.task_groups)
      end

      --Add self to job_info_controllers
      if self:get_job_info() then
         self:get_job_info():add_member(self._entity)
      end

      --Log in journal, if possible
      local activity_name = self._job_json.promotion_activity_name
      if activity_name then
         radiant.events.trigger_async(stonehearth.personality, 'stonehearth:journal_event',
                             {entity = self._entity, description = activity_name})
      end

      --Post bulletin
      local attributes_component = self._entity:get_component('stonehearth:attributes')

      --Add all the universal level dependent buffs/bonuses, etc
      local job_name = self._job_json.display_name
      local has_class_perks = false
      if #class_perk_descriptions > 0 then
         has_class_perks = true
      end

      local player_id = radiant.entities.get_player_id(self._entity)
      local name = radiant.entities.get_display_name(self._entity)
      local title = self._default_promote_announcement

      if (not options or not options.skip_visual_effects) and has_class_perks and first_time_job then
         --post the bulletin
         local level_bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
            :set_ui_view('StonehearthPromoteBulletinDialog')
            :set_callback_instance(self)
            :set_data({
               title = title,
               char_name = name,
               zoom_to_entity = self._entity,
               has_class_perks = has_class_perks,
               class_perks = class_perk_descriptions
            })
            :set_active_duration('1h')
            :add_i18n_data('entity_display_name', radiant.entities.get_display_name(self._entity))
            :add_i18n_data('entity_custom_name', radiant.entities.get_custom_name(self._entity))
            :add_i18n_data('entity_custom_data', radiant.entities.get_custom_data(self._entity))
            :add_i18n_data('job_name', job_name)
            :add_i18n_data('level_number', self._sv.curr_job_level)
      end

      -- so good!  keep this one, lose the top one.  too much "collusion" between components =)
      radiant.events.trigger(self._entity, 'stonehearth:job_changed', { entity = self._entity })
      self.__saved_variables:mark_changed()
   end

	-- add the training toggle command if not max level
	if self:is_trainable() then
		self:_add_training_toggle()
   end
   
   if self:has_multiple_equipment_preferences() then
      self:_add_equipment_preferences_toggle()
   end

   self:_register_entity_types()

   self._sv.current_talisman_uri = talisman_entity and talisman_entity:get_uri()

	--radiant.events.trigger(self._entity, 'stonehearth_ace:on_promote', { job_uri = job_uri, options = options })
end

AceJobComponent._ace_old_demote = JobComponent.demote
function AceJobComponent:demote(old_job_json, dont_drop_talisman)
   self._sv._job_equipment_uris = {}

   self:_ace_old_demote(old_job_json, dont_drop_talisman)

	-- remove the training toggle command if it exists
	self:_remove_training_toggle()
   
   self:_remove_equipment_preferences_toggle()

   self:_unregister_entity_types()

	radiant.events.trigger(self._entity, 'stonehearth_ace:on_demote', { old_job_json = old_job_json, dont_drop_talisman = dont_drop_talisman })
end

--AceJobComponent._ace_old__equip_equipment = JobComponent._equip_equipment
function AceJobComponent:_equip_equipment(json, talisman_entity)
   self._sv._job_equipment_uris = {}
   
   local equipment_component = self._entity:add_component('stonehearth:equipment')
   if json and json.equipment then
      local talisman_data = talisman_entity and radiant.entities.get_entity_data(talisman_entity, 'stonehearth_ace:promotion_talisman')
      local equipment_overrides = talisman_data and talisman_data.equipment_overrides or {}
      -- iterate through the equipment in the table, placing one item from each value
      -- on the entity.  they of the entry are irrelevant: they're just for documenation
      for slot, json_items in pairs(json.equipment) do
         local items = equipment_overrides[slot] or json_items
         local item
         if type(items) == 'string' then
            -- create this piece
            item = items
         elseif type(items) == 'table' then
            -- pick a random item from the array
            item = items[rng:get_int(1, #items)]
         end

         if item and item ~= '' then
            local equipment = radiant.entities.create_entity(item)
            local unequipped_item = equipment_component:equip_item(equipment, false)
            if unequipped_item then
               -- if the unequipped item is the same as the equipped one or shouldn't be dropped, delete it
               local location = radiant.entities.get_world_grid_location(self._entity)
               local ep_comp = unequipped_item:get_component('stonehearth:equipment_piece')
               if location and unequipped_item:get_uri() ~= item and (not ep_comp or ep_comp:get_should_drop()) then
                  local placement_point = radiant.terrain.find_placement_point(location, 1, 4)
                  radiant.terrain.place_entity(unequipped_item, placement_point)
               else
                  -- can happen duing re-embarkation with classes upgraded from classes that have equipment to drop.
                  radiant.entities.destroy_entity(unequipped_item)
               end
            end
            table.insert(self._sv._job_equipment, equipment)
            self._sv._job_equipment_uris[equipment:get_component('stonehearth:equipment_piece'):get_slot()] = equipment:get_uri()
         end
      end
   end
end

-- Drops the talisman near the location of the entity, returns the talisman entity
-- If the class has something to say about the talisman before it goes, do that first
function AceJobComponent:_drop_talisman(old_job_json)
   if old_job_json and not stonehearth.player:is_npc(self._entity) then
      local talisman_uri = self._sv.current_talisman_uri or old_job_json.talisman_uri
      if talisman_uri then
         self._sv.current_talisman_uri = nil
         local location = radiant.entities.get_world_grid_location(self._entity)
         local player_id = radiant.entities.get_player_id(self._entity)
         local output_table = {}
         output_table[talisman_uri] = 1
         --TODO: is it possible that this gets dumped onto an inaccessible location?
         local items = radiant.entities.spawn_items(output_table, location, 1, 2, { owner = player_id })
         local inventory = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(self._entity))
         if inventory then
            for _, item in pairs(items) do
               inventory:add_item(item) -- Force add talisman to inventory
            end
         end
      end
   end
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

AceJobComponent._ace_old__update_job_work_order = JobComponent._update_job_work_order
function AceJobComponent:_update_job_work_order(player_id)
   if self._training_target and self._training_target:get_player_id() ~= player_id then
      self._training_target = nil
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
   local job_controller = self:get_curr_job_controller()
   return job_controller and job_controller.is_trainable and job_controller:is_trainable()
end

function AceJobComponent:get_training_enabled()
	return radiant.entities.get_attribute(self._entity, 'stonehearth_ace:training_enabled', 1) == 1
end

function AceJobComponent:set_training_enabled(enabled)
	local prev_enabled = self:get_training_enabled()
   radiant.entities.set_attribute(self._entity, 'stonehearth_ace:training_enabled', enabled and 1 or 0)
   if prev_enabled ~= enabled then
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:training_enabled_changed', enabled)
   end
end

function AceJobComponent:toggle_training(enabled)
   self:set_training_enabled(enabled)
	if self:is_trainable() then
      self:_add_training_toggle(enabled)
   else
      self:_remove_training_toggle()
	end
end

function AceJobComponent:get_training_target()
   local target = self._training_target
   if target then
      if not target:is_valid() or radiant.entities.get_work_player_id(self._entity) ~= target:get_player_id() then
         target = nil
         self._training_target = nil
      end
   end
   return target
end

function AceJobComponent:set_training_target(target)
   self._training_target = target
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
		commands_component = self._entity:get_component('stonehearth:commands')
	end

   if commands_component then
      if commands_component:has_command(disable) then
         commands_component:remove_command(disable)
      end
      if commands_component:has_command(enable) then
         commands_component:remove_command(enable)
      end
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
   local commands_component = self._entity:get_component('stonehearth:commands')
   if commands_component and self._sv.current_equipment_preferences_command then
      commands_component:remove_command(self._sv.current_equipment_preferences_command)
   end
end

return AceJobComponent