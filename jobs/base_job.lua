local constants = require 'stonehearth.constants'

local BaseJob = class()

--[[
   A base class for all classes. Contains getters for job variables common to all classes
   TODO: Move functions out of classes that inherit from this class if its function is identical to the one here
]]

function BaseJob:initialize()
   self._sv._entity = nil
   self._sv._alias = nil
   self._sv.json_path = nil
   self._sv.last_gained_lv = 1
   self._sv.is_current_class = false
   self._sv.equipment = {}
   self._sv.attained_perks = {}
   -- ADDED FOR ACE
   self._sv.max_num_training = {}
   self._sv._lookup_values = {}
   self._sv._can_repair_as_jobs = {}
   self._sv._can_repair_as_any_job = false

   -- These are for the UI only
   self._sv.is_max_level = false
   self._sv.no_levels = false
   self._sv.is_combat_class = false

   self._xp_rewards = {}
   self._level_data = {}
   self._job_json = nil
   self._max_level = 0
end

function BaseJob:create(entity)
   self._sv._entity = entity
end

function BaseJob:activate()
   self:_load_json_tuning()

   self._job_component = self._sv._entity:get_component('stonehearth:job')

   --If we load and we're the current class, do these things
   if self._sv.is_current_class then
      if self._create_listeners then
         self:_create_listeners()
      end

      self:_register_with_town()
   end
end

function BaseJob:restore()
   if self._sv.lookup_values then
      self._sv._lookup_values = self._sv.lookup_values
      self._sv.lookup_values = nil
   end
   if self._sv.equipment_prefs then
      self._sv._equipment_prefs = self._sv.equipment_prefs
      self._sv.equipment_prefs = nil
   end
   if self._sv.equipment_roles_ordered then
      self._sv._equipment_roles_ordered = self._sv.equipment_roles_ordered
      self._sv.equipment_roles_ordered = nil
   end
   if self._sv.equipment_role then
      self._sv._equipment_role = self._sv.equipment_role
      self._sv.equipment_role = nil
   end

   if not self._sv.json_path then
      self._sv.json_path = self._sv._json_path
      self._sv._json_path = nil
   end
   if self._sv.is_current_class then
      self:_register_with_town()
   end
end

function BaseJob:fixup_job_json_path(json_path)
   self._sv.json_path = json_path
   self:_load_json_tuning()
end

function BaseJob:_load_json_tuning()
   if not self._sv.json_path then
      return
   end

   self._job_json = radiant.resources.load_json(self._sv.json_path, true)
   if self._job_json.xp_rewards then
      self._xp_rewards = self._job_json.xp_rewards
   end

   if self._job_json.level_data then
      self._level_data = self._job_json.level_data
   end

   self._max_level = self._job_json.max_level or 0
   self._max_training_level = self._job_json.max_training_level or 0
   
   if self._sv.last_gained_lv >= self._max_level then
      self._sv.is_max_level = true
   else
      self._sv.is_max_level = false
   end
end

function BaseJob:promote(json_path)
   self._sv.is_current_class = true
   self._sv.json_path = json_path
   self:_load_json_tuning()
   local entity = self._sv._entity

   if not self._sv.is_combat_class then
      --Unless you are a combat class (role is combat) remove self
      --from any preexisting parties on promote
      --clear self of any combat commands
      local curr_party = stonehearth.unit_control:get_party_for_entity_command({}, {}, entity)
      if curr_party then
         local party_component = curr_party:get_component('stonehearth:party')
         if party_component then
            party_component:remove_member(entity:get_id())
         end
      end
      stonehearth.combat_server_commands:clear_entity_of_combat_commands(entity:get_id())
   end

   if self._create_listeners then
      self:_create_listeners()
   end

   -- ADDED FOR ACE
   self:_add_commands()
   self:_register_with_town()
end

function BaseJob:level_up()
   self._sv.last_gained_lv = self._sv.last_gained_lv + 1

   if self._sv.last_gained_lv >= self._max_level then
      self._sv.is_max_level = true
   end
   self.__saved_variables:mark_changed()
end

-- Returns the level the character has in this class
function BaseJob:get_job_level()
   return self._sv.last_gained_lv
end

-- Returns whether we're at max level.
function BaseJob:is_max_level()
   return self._sv.is_max_level
end

function BaseJob:can_level_up()
   if self._sv.no_levels or self:is_max_level() then
      return false
   end
   return true
end

function BaseJob:get_max_training_level()
   return self._max_training_level
end

function BaseJob:is_trainable()
   return self._sv.last_gained_lv <= self._max_training_level
end

-- Returns all the data for all the levels
function BaseJob:get_level_data()
   return self._level_data
end

-- Given the ID of a perk, find out if we have the perk. 
function BaseJob:has_perk(id)
   return self._sv.attained_perks[id]
end

function BaseJob:demote()
   self._sv.is_current_class = false

   if self._remove_listeners then
      self:_remove_listeners()
   end

   self.__saved_variables:mark_changed()
   
   -- ADDED FOR ACE
   
   -- make sure the job json is loaded so we can remove commands and any other stuff dependent on the job
   if not self._job_json then
      self._job_json = radiant.resources.load_json(self._sv.json_path, true)
   end

   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:remove_placement_slot_entity(self._sv._entity)
   end
   
   self:_remove_commands()
end

function BaseJob:destroy()
   if self._sv.is_current_class then
      -- if we were destroyed without demote
      if self._remove_listeners then
         self:_remove_listeners()
      end
   end
end

-- We keep an index of perks we've unlocked for easy lookup
function BaseJob:unlock_perk(id)
   self._sv.attained_perks[id] = true
   self.__saved_variables:mark_changed()
end

-- Shared Perk Application functionality
function BaseJob:apply_chained_buff(args)
   radiant.entities.remove_buff(self._sv._entity, args.last_buff)
   radiant.entities.add_buff(self._sv._entity, args.buff_name)   
end

function BaseJob:apply_buff(args)
   radiant.entities.add_buff(self._sv._entity, args.buff_name)   
end

function BaseJob:remove_buff(args)
   radiant.entities.remove_buff(self._sv._entity, args.buff_name)
end

function BaseJob:add_equipment(args)
   local equipment = radiant.entities.create_entity(args.equipment)
   self._sv.equipment[args.equipment] = equipment
   radiant.entities.equip_item(self._sv._entity, equipment)
end

-- Remove equipment from the character
function BaseJob:remove_equipment(args)
   local equipment = self._sv.equipment[args.equipment]
   if equipment then
      radiant.entities.unequip_item(self._sv._entity, equipment)
      radiant.entities.destroy_entity(equipment)
      self._sv.equipment[args.equipment] = nil
   end
end

function BaseJob:apply_chained_equipment(args)
   local old_equipment_args = {
      equipment = args.last_equipment
   }
   self:remove_equipment(old_equipment_args)
   self:add_equipment(args)
end

-- BELOW FUNCTIONS ADDED IN ACE:

function BaseJob:get_all_equipment_preferences()
   if not self._sv._equipment_prefs or not self._sv._equipment_roles_ordered then
      self._sv._equipment_prefs = {}
      self._sv._equipment_roles_ordered = {}
      self._sv._equipment_role = nil

      local equipment_prefs = self._job_json.equipment_preferences
      if equipment_prefs and equipment_prefs.roles then
         for role, prefs in pairs(equipment_prefs.roles) do
            self._sv._equipment_prefs[role] = {
               types = prefs.types,
               multiplier = prefs.multiplier,
               command = prefs.command,
            }
            table.insert(self._sv._equipment_roles_ordered, role)
         end
         table.sort(self._sv._equipment_roles_ordered)
         self:set_equipment_role(equipment_prefs.default_role)
      end

      --self.__saved_variables:mark_changed()
   end

   return self._sv._equipment_prefs
end

function BaseJob:get_equipment_preferences()
   local prefs = self:get_all_equipment_preferences()
   local role = self:get_equipment_role()
   return role and prefs and prefs[role]
end

function BaseJob:get_equipment_roles()
   self:get_all_equipment_preferences()
   return self._sv._equipment_roles_ordered
end

function BaseJob:get_equipment_role()
   return self._sv._equipment_role
end

function BaseJob:set_equipment_role(role)
   if self._sv._equipment_role ~= role then
      self:_remove_current_role_buffs()
      self._sv._equipment_role = role
      self:_add_current_role_buffs()
      --self.__saved_variables:mark_changed()

      radiant.events.trigger_async(self._sv._entity, 'stonehearth_ace:equipment_role_changed')
      
      return role
   end
end

function BaseJob:set_next_equipment_role(from_role)
   -- if the current equipment role is nil or cannot be found, set the role to the first one
   -- otherwise set it to the next one in the list, wrapping around to the first
   self:get_all_equipment_preferences()
   local roles = self._sv._equipment_roles_ordered
   local cur_role = from_role or self:get_equipment_role()
   local new_role
   local first

   for i, role in ipairs(roles) do
      if not first then
         first = role
         if not cur_role then
            break
         end
      end
      if role == cur_role then
         local temp
         temp, new_role = next(roles, i)
         break
      end
   end

   return self:set_equipment_role(new_role or first)
end

function BaseJob:increase_max_placeable_training(args)
   self._sv.max_num_training = args.max_num_training
   self:_register_with_town()
   self.__saved_variables:mark_changed()
end

function BaseJob:_register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_training)
   end
end

function BaseJob:get_lookup_value(key)
   return self._sv._lookup_values[key]
end

function BaseJob:set_lookup_values(args)
   if args.lookup_values then
      for key, value in pairs(args.lookup_values) do
         self._sv._lookup_values[key] = value
      end
      self.__saved_variables:mark_changed()
   end
end

function BaseJob:_add_commands()
   local to_add = self._job_json.commands and self._job_json.commands.add_on_promote
   if to_add then
      local command_comp = self._sv._entity:add_component('stonehearth:commands')
      for _, command in ipairs(to_add) do
         command_comp:add_command(command)
      end
   end
end

function BaseJob:_remove_commands()
   local to_remove = self._job_json.commands and self._job_json.commands.remove_on_demote
   if to_remove then
      local command_comp = self._sv._entity:add_component('stonehearth:commands')
      for _, command in ipairs(to_remove) do
         command_comp:remove_command(command)
      end
   end
end

function BaseJob:add_perk_commands(args)
   if args.commands then
      local command_comp = self._sv._entity:add_component('stonehearth:commands')
      for _, command in ipairs(args.commands) do
         command_comp:add_command(command)
      end
   end
end

function BaseJob:remove_perk_commands(args)
   if args.commands then
      local command_comp = self._sv._entity:get_component('stonehearth:commands')
      if command_comp then
         for _, command in ipairs(args.commands) do
            command_comp:remove_command(command)
         end
      end
   end
end

function BaseJob:allow_hunting(args)
   local command_comp = self._sv._entity:add_component('stonehearth:commands')
   local avoid_hunting = self._sv._entity:add_component('stonehearth:properties'):has_property('avoid_hunting')
   if avoid_hunting then
      command_comp:add_command('stonehearth_ace:commands:allow_hunting')
   else
      command_comp:add_command('stonehearth_ace:commands:avoid_hunting')
   end
end

function BaseJob:add_equipment_role_buffs(args)
   local role_buffs = self:_get_current_equipment_role_buffs()

   -- if there are buffs for the current role and the new setting changes it, remove the current buffs
   if role_buffs then
      local new_role_buffs = args.equipment_role_buffs[self:get_equipment_role()]
      -- check for nil, because if it's false (or an array that's empty or contains buffs), we want to remove existing buffs
      if new_role_buffs ~= nil then
         self:_remove_current_role_buffs(role_buffs)
      end
   end

   self._sv._equipment_role_buffs = radiant.util.merge_into_table(self._sv._equipment_role_buffs or {}, args.equipment_role_buffs)
   self:_add_current_role_buffs()
end

function BaseJob:remove_equipment_role_buffs(args)
   self:_remove_current_role_buffs()
   self._sv._equipment_role_buffs = nil
end

function BaseJob:unlock_town_ability(args)
   local pop = stonehearth.population:get_population(self._sv._entity)
   if pop and args.unlock_ability then
      pop:unlock_ability(args.unlock_ability)
   end
end

function BaseJob:get_current_level_exp()
   if self._job_json.save_current_level_experience then
      return math.floor((self._sv._current_level_exp or 0) * (self._job_json.save_current_level_experience_multiplier or 1))
   end
end

function BaseJob:set_current_level_exp(exp)
   if self._job_json.save_current_level_experience then
      self._sv._current_level_exp = exp
   end
end

function BaseJob:_get_current_equipment_role_buffs()
   local prefs = self:get_equipment_preferences()
   local role = self:get_equipment_role()
   local buffs = self._sv._equipment_role_buffs

   return role and buffs and buffs[role]
end

function BaseJob:_remove_current_role_buffs(buffs)
   buffs = buffs or self:_get_current_equipment_role_buffs()
   if buffs then
      for _, buff in ipairs(buffs) do
         radiant.entities.remove_buff(self._sv._entity, buff)
      end
   end
end

function BaseJob:_add_current_role_buffs()
   local buffs = self:_get_current_equipment_role_buffs()
   if buffs then
      for _, buff in ipairs(buffs) do
         radiant.entities.add_buff(self._sv._entity, buff)
      end
   end
end

function BaseJob:get_medic_capabilities()
   return self._sv._medic_capabilities
end

function BaseJob:set_medic_capabilities(args)
   if args.medic_capabilities then
      self._sv._medic_capabilities = args.medic_capabilities
      radiant.events.trigger_async(self._sv._entity, 'stonehearth_ace:medic_capabilities_changed', args.medic_capabilities)
   end
end

function BaseJob:remove_medic_capabilities(args)
   self._sv._medic_capabilities = nil
   radiant.events.trigger_async(self._sv._entity, 'stonehearth_ace:medic_capabilities_changed')
end

function BaseJob:add_can_repair_as_jobs(args)
   self._sv._can_repair_as_jobs = radiant.util.merge_into_table(self._sv._can_repair_as_jobs, args.can_repair_as_jobs)
   radiant.events.trigger_async(self._sv._entity, 'stonehearth_ace:repair_capabilities_changed')
end

function BaseJob:remove_can_repair_as_jobs(args)
   self._sv._can_repair_as_jobs = {}
   radiant.events.trigger_async(self._sv._entity, 'stonehearth_ace:repair_capabilities_changed')
end

function BaseJob:set_can_repair_as_any_job(args)
   self._sv._can_repair_as_any_job = true
   radiant.events.trigger_async(self._sv._entity, 'stonehearth_ace:repair_capabilities_changed')
end

function BaseJob:remove_can_repair_as_any_job(args)
   self._sv._can_repair_as_any_job = false
   radiant.events.trigger_async(self._sv._entity, 'stonehearth_ace:repair_capabilities_changed')
end

function BaseJob:get_can_repair_as_jobs()
   return self._sv._can_repair_as_jobs
end

function BaseJob:can_repair_as_job(job_uri)
   return job_uri == self._sv._alias or self._sv._can_repair_as_jobs[job_uri]
end

function BaseJob:can_repair_as_any_job()
   return self._sv._can_repair_as_any_job
end

function BaseJob:is_trapper()
   return false
end

function BaseJob:is_farmer()
   return false
end

return BaseJob
