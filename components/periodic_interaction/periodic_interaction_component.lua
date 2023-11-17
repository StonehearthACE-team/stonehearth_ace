--[[
   Behaves similarly to 'stonehearth:workshop':
    - gets "reserved" by a single person at a time; only that person can use it until the interaction sequence is complete
    - if that person changes jobs, they'll unreserve it
   Allow for selection of none, all, or a specific qualified user with ownership-style UI
   Allow for selection of one of many "modes" of interaction with a dropdown (hide if only one mode available)
    - each mode has usage requirements (job, level, general cooldown, eqiupped item, etc.)
    - each mode can specify multiple weighted sequences; selection is chosen on activate for all modes
    - each sequence specifies one or more ordered interactions
    - each interaction has a cooldown, possible rewards, chance to complete the sequence, required ingredient?

   json component data (most fields are optional):
   "stonehearth_ace:periodic_interaction": {
      "default_model": "model_name",
      "reset_effect": "stonehearth_ace:effects:reset_effect",
      "transform_after_using_key": "disable_after_use",
      "transform_after_num_uses": 5,
      "allow_mode_selection": true,
      "interaction_points": {
         "point1": {
            "point": [
               -1,
               0,
               0.5
            ],
            "face_point": [
               1,
               0,
               0
            ]
         },
         "point2": {
            "point": [
               0.5,
               0,
               -1.5
            ],
            "face_point": [
               0,
               0,
               1
            ]
         },
         "point3": {
            "point": [
               -1.5,
               0,
               -1
            ],
            "face_point": [
               -1,
               0,
               0
            ]
         },
      },
      "modes": {
         "find_native_seed": {
            "ai_status_key": "stonehearth_ace:ai.actions.status_text.periodic_interaction.find_native_seed.default",
            "ui_data": {
               "display_name": "i18n(stonehearth_ace:jobs.herbalist.herbalist_exploration_garden.periodic_interaction.modes.find_native_seed.name)",
               "description": "i18n(stonehearth_ace:jobs.herbalist.herbalist_exploration_garden.periodic_interaction.modes.find_native_seed.description)"
            },
            "cooldown": "12h",
            "requirements": {
               "job": "stonehearth:jobs:herbalist",
               "level": 2,
               "equipped_item": "stonehearth_ace:herbalist:tools:simple_trowel"
            },
            "completion": {
               "rewards": [
                  {
                     "type": "experience",
                     "value": 25
                  }
               ]
            },
            "sequences": {  "__comment": "keys here are just for the designer's convenience",
               "quick": [
                  {
                     "effect": "stonehearth_ace:effects:static_effect",
                     "interaction_effect": "stonehearth_ace:effects:something_happens",
                     "cooldown": "4h",
                     "model": "stage_1",
                     "num_interactions": 3,
                     "ai_status_key": "stonehearth_ace:ai.actions.status_text.periodic_interaction.find_native_seed.specific_1",
                     "worker_effect": "fiddle",
                     "interaction_points": {
                        "point1": {
                           "weight": 3,
                        },
                        "point2": {},
                        "point3": {}
                     },
                     "rewards": [
                        {
                           "type": "experience",
                           "value": 10
                        },
                        {
                           "type": "script",
                           "script": "stonehearth_ace:scripts:periodic_interaction:herbalist_exploration_garden:rewards",
                           "script_data": {
                              "crop_category": "herb",
                              "none": 90,
                              "native": 10
                           }
                        }
                     ]
                  },
                  {
                     "effect": "stonehearth_ace:effects:static_effect",
                     "interaction_effect": "stonehearth_ace:effects:something_happens",
                     "cooldown": "4h",
                     "model": "stage_2",
                     "num_interactions": 3,
                     "interaction_points": {
                        "point1": {},
                        "point2": {
                           "weight": 3
                        },
                        "point3": {}
                     },
                     "rewards": [
                        {
                           "type": "experience",
                           "value": 10
                        },
                        {
                           "type": "script",
                           "script": "stonehearth_ace:scripts:periodic_interaction:herbalist_exploration_garden:rewards",
                           "script_data": {
                              "crop_category": "herb",
                              "none": 69,
                              "native": 30,
                              "exotic": 1
                           }
                        }
                     ]
                  },
                  {
                     "effect": "stonehearth_ace:effects:static_effect",
                     "interaction_effect": "stonehearth_ace:effects:something_happens",
                     "model": "stage_3",
                     "num_interactions": 3,
                     "interaction_points": {
                        "point1": {},
                        "point2": {},
                        "point3": {
                           "weight": 3
                        }
                     },
                     "rewards": [
                        {
                           "type": "experience",
                           "value": 10
                        },
                        {
                           "type": "script",
                           "script": "stonehearth_ace:scripts:periodic_interaction:herbalist_exploration_garden:rewards",
                           "script_data": {
                              "crop_category": "herb",
                              "native": 95,
                              "exotic": 5
                           }
                        }
                     ]
                  }
               ]
            }
         },
         "find_exotic_seed": {

         }
      }
   }
]]

local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local rng = _radiant.math.get_default_rng()

local PI_TASK_GROUP = 'stonehearth_ace:task_groups:periodic_interaction'
local PI_ACTION = 'stonehearth_ace:periodic_interaction'
local PI_WITH_INGREDIENT_ACTION = 'stonehearth_ace:periodic_interaction_with_ingredient'

local PeriodicInteractionComponent = class()

local log = radiant.log.create_logger('periodic_interaction')

function PeriodicInteractionComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}

   self._sv._mode_sequences = {}
   self._sv.ui_data = {}
   self._sv.current_mode = nil
   self._sv.current_user = nil
   self._sv.current_owner = nil
   self._sv.ingredient_quality = nil
   self._sv.interaction_stage = 1
   self._sv.num_uses = 0
   self._sv.enabled = self._json.start_enabled ~= false
   self._sv.allow_mode_selection = self._json.allow_mode_selection ~= false
   self._sv.allow_non_owner_player_interaction = self._json.allow_non_owner_player_interaction
   self._sv._general_cooldown_timer = nil
   self._sv._interaction_cooldown_timer = nil

   self._added_interaction_tasks = {}
end

function PeriodicInteractionComponent:activate()
   self:_select_mode_sequences()
   self:_load_current_mode_data(self._sv.current_mode)
end

function PeriodicInteractionComponent:post_activate()
   --Trace the parent to figure out if it's added or not:
   self._parent_trace = self._entity:add_component('mob'):trace_parent('periodic_interaction added or removed from world')
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world
               self:_shutdown()
            else
               --we were just added to the world
               self:_startup()
            end
         end)

   self:_setup_ui_data()
   self:_startup()
end

function PeriodicInteractionComponent:destroy()
   self:_destroy_current_user_job_listener()
   self:_destroy_eligibility_listeners()
   self:_destroy_interaction_tasks()
   self:_stop_interaction_cooldown_timer()
   self:_stop_general_cooldown_timer()
   self:_stop_evolve_timer()
   
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   if self._interaction_stage_effect then
      self._interaction_stage_effect:stop()
      self._interaction_stage_effect = nil
   end
   if self._interaction_effect then
      self._interaction_effect:stop()
      self._interaction_effect = nil
   end
end

function PeriodicInteractionComponent:_destroy_eligibility_listeners()
   if self._eligibility_listeners then
      for _, listener in ipairs(self._eligibility_listeners) do
         listener:destroy()
      end

      self._eligibility_listeners = nil
   end
end

function PeriodicInteractionComponent:_setup_usability_listeners()
   self:_destroy_eligibility_listeners()
   local listeners = {}

   local jobs_controller = stonehearth.job:get_jobs_controller(self._entity:get_player_id())
   
   local job_level_listener = radiant.events.listen(jobs_controller, 'stonehearth_ace:job:highest_level_changed', function(args)
         self:_check_modes_for_valid_job_levels(args.job_uri, args.highest_level)
      end)

   table.insert(listeners, job_level_listener)

   self._eligibility_listeners = listeners
end

function PeriodicInteractionComponent:_create_current_user_job_listener()
   self:_destroy_current_user_job_listener()
   local current_user = self._sv.current_user
   if current_user and current_user:is_valid() then
      self._current_user_job_listener = radiant.events.listen(current_user, 'stonehearth:job_changed', function()
            -- check if they can still use this entity; otherwise, reset current user and owner
            if not self:is_valid_potential_user(current_user) then
               self._sv.current_owner = nil
               self:cancel_using(current_user)
            end
         end)
   end
end

function PeriodicInteractionComponent:_destroy_current_user_job_listener()
   if self._current_user_job_listener then
      self._current_user_job_listener:destroy()
      self._current_user_job_listener = nil
   end
end

function PeriodicInteractionComponent:_startup()
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end

   self:select_mode(self._sv.current_mode)
   self:_setup_usability_listeners()
   self:_create_current_user_job_listener()
end

function PeriodicInteractionComponent:_shutdown()
   self:cancel_using(self._sv.current_user, true)
   self:_destroy_eligibility_listeners()
   self:_destroy_current_user_job_listener()
   self:_stop_evolve_timer()
end

function PeriodicInteractionComponent:get_valid_users_command(session, response)
   local users = self:get_valid_potential_users()
   response:resolve({users = users})
end

function PeriodicInteractionComponent:set_enabled_command(session, response, enabled)
   self:set_enabled(enabled)
   return true
end

function PeriodicInteractionComponent:select_mode_command(session, response, mode)
   -- don't do anything if it's already this mode
   if mode ~= self._sv.current_mode then
      self:_reset(false, true)
      self:select_mode(mode)
      return true
   end
end

function PeriodicInteractionComponent:set_owner_command(session, response, owner)
   if owner ~= self._sv.current_owner then
      self._sv.current_owner = owner
      self.__saved_variables:mark_changed()
      -- actual usability isn't changing here, but who is allowed to use it is
      stonehearth.ai:reconsider_entity(self._entity, 'stonehearth_ace:periodic_interaction')
      return true
   end
end

function PeriodicInteractionComponent:is_enabled()
   return self._sv.enabled
end

function PeriodicInteractionComponent:set_enabled(enabled)
   if self._sv.enabled ~= enabled then
      self._sv.enabled = enabled
      self.__saved_variables:mark_changed()
      self:_consider_usability()
   end
end

function PeriodicInteractionComponent:get_current_mode()
   return self._sv.current_mode
end

function PeriodicInteractionComponent:get_current_owner()
   return self._sv.current_owner
end

function PeriodicInteractionComponent:get_current_user()
   return self._sv.current_user or self._sv.current_owner
end

function PeriodicInteractionComponent:is_usable()
   return self._is_usable
end

function PeriodicInteractionComponent:cancel_using(user, force_reset)
   if self._sv.current_user == user then
      -- only reset if the current mode requires a reset on cancel
      if force_reset or (self._current_mode_data and self._current_mode_data.reset_on_cancel) then
         self:_reset(false, true)
      end
      self:_cancel_usage()
   end
end

function PeriodicInteractionComponent:_reset(completed, skip_mode_reselection)
   log:debug('%s _reset(%s, %s)', self._entity, tostring(completed), tostring(skip_mode_reselection))
   self._sv.interaction_stage = 1

   -- if the interaction was completed, handle any rewards and then clear out the current sequence for it and set up a new one
   if completed then
      local completion_data = self._current_mode_data.completion
      if completion_data then
         if completion_data.rewards then
            self:_apply_rewards(completion_data.rewards, true)
         end
      end

      if self._json.reset_effect then
         radiant.effects.run_effect(self._entity, self._json.reset_effect)
      end

      self._sv._mode_sequences[self._sv.current_mode] = nil
      self._sv.num_uses = self._sv.num_uses + 1     

      if self._json.transform_after_using_key and self._json.transform_after_num_uses and self._sv.num_uses >= self._json.transform_after_num_uses then
         -- instead of doing any other resetting at this point, transform the entity
         local transform_comp = self._entity:add_component('stonehearth_ace:transform')
         if transform_comp then
            transform_comp:set_transform_option(self._json.transform_after_using_key)
            transform_comp:request_transform(self._entity:get_player_id())
            return
         end
      else
         self._entity:add_component('render_info'):set_model_variant(self._json.default_model or 'default')
      end

      self:_select_mode_sequences()
   end

   self._sv.current_user = nil
   self._sv.ingredient_quality = nil
   self.__saved_variables:mark_changed()
   self:_destroy_current_user_job_listener()

   if not skip_mode_reselection then   
      self:select_mode(self._sv.current_mode)
   else
      self:_consider_usability(true)
   end
end

function PeriodicInteractionComponent:_cancel_usage()
   self._sv.current_user = nil
   self.__saved_variables:mark_changed()
   self:_destroy_current_user_job_listener()
   self:_consider_usability(true)
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:periodic_interaction:cancel_usage')
end

function PeriodicInteractionComponent:_setup_ui_data()
   local jobs_controller = stonehearth.job:get_jobs_controller(self._entity:get_player_id())

   for id, data in pairs(self._json.modes) do
      self._sv.ui_data[id] = radiant.shallow_copy(data.ui_data)

      -- check job eligibility
      if data.requirements and data.requirements.job then
         local job = jobs_controller:get_job(data.requirements.job)
         local max_level = job and job:get_highest_level()

         self._sv.ui_data[id].has_eligible_job = max_level and max_level >= (data.requirements.level or 1)
      end
   end
   self._sv.show_mode_selection = self._json.show_mode_selection

   self.__saved_variables:mark_changed()
end

function PeriodicInteractionComponent:_setup_mode_ui_data()
   local stages
   if self._current_mode_data.allow_finish_stage_selection then
      -- prepare some basic data about all the selectable stages to remote to the ui
      -- stage index, name, description, ...?
      stages = {}
      for index, stage in ipairs(self._current_sequence_data) do
         if stage.allow_finish_selection then
            table.insert(stages, {
               index = index,
               display_name = stage.display_name,
               description = stage.description,
               icon = stage.icon,
            })
         end
      end
   end

   self._sv.stages = stages
   self._sv.allow_finish_stage_selection = self._current_mode_data.allow_finish_stage_selection
   self.__saved_variables:mark_changed()
end

function PeriodicInteractionComponent:_select_mode_sequences()
   -- remove any modes that don't have a definition in the json
   for id, _ in pairs(self._sv._mode_sequences) do
      if not self._json.modes[id] then
         self._sv._mode_sequences[id] = nil
      end
   end

   for id, data in pairs(self._json.modes) do
      if self._sv._mode_sequences[id] == nil then
         local sequences = WeightedSet(rng)
         for key, sequence in pairs(data.sequences) do
            sequences:add(key, sequence.weight or 1)
         end
         self._sv._mode_sequences[id] = sequences:choose_random()
      end
   end
end

function PeriodicInteractionComponent:_load_current_mode_data(mode)
   mode = mode or self._json.default_mode
   if not mode or not self._sv._mode_sequences[mode] then
      mode = next(self._sv._mode_sequences)
   end
   
   self._current_mode_data = self._json.modes[mode]
   self._current_sequence = self._sv._mode_sequences[mode]
   self._current_sequence_data = self._current_mode_data.sequences[self._current_sequence]
   if not self._sv.finish_stage then
      self._sv.finish_stage = self._current_mode_data.default_finish_stage or #self._current_sequence_data
      self.__saved_variables:mark_changed()
   end

   return mode
end

-- this should only get called when the mode has changed or on startup/reset
function PeriodicInteractionComponent:select_mode(mode)
   mode = self:_load_current_mode_data(mode)

   if mode ~= self._sv.current_mode then
      self._sv.current_mode = mode
      self._sv.finish_stage = self._current_mode_data.default_finish_stage or #self._current_sequence_data
      self:_cancel_usage()
   end

   self:_setup_mode_ui_data()

   self:_stop_evolve_timer()
   self:_stop_interaction_cooldown_timer()
   self:_apply_current_stage_settings()
   self:_consider_usability(true)
end

function PeriodicInteractionComponent:get_current_mode_ai_status()
   local status = self._current_mode_data and self._current_mode_data.ai_status_key
   return status or 'stonehearth_ace:ai.actions.status_text.periodic_interaction.default'
end

function PeriodicInteractionComponent:get_valid_potential_users()
   local users = {}
   local pop = stonehearth.population:get_population(self._entity)

   for id, citizen in pop:get_citizens():each() do
      if self:is_valid_potential_user(citizen) then
         table.insert(users, citizen)
      end
   end

   return users
end

function PeriodicInteractionComponent:get_current_mode_requirements()
   return self._current_mode_data.requirements
end

function PeriodicInteractionComponent:is_valid_potential_user(entity)
   if entity and entity:is_valid() then
      if self._sv.current_user and self._sv.current_user:is_valid() and entity ~= self._sv.current_user then
         return false
      end

      local requirements = self._current_mode_data.requirements
      
      if requirements.job then
         local job_component = entity:get_component('stonehearth:job')
         if not job_component or job_component:get_job_uri() ~= requirements.job then
            return false
         end

         if requirements.level and job_component:get_current_job_level() < requirements.level then
            return false
         end
      end

      -- technically supported, but it's probably simpler to just use any_active_buff instead
      -- and have the buff added by the equipment
      if requirements.any_equipped_item then
         local equipment_component = entity:get_component('stonehearth:equipment')
         if not equipment_component then
            return false
         end

         -- go through all of the items specified in any_equipped_item
         -- if *any* of them are equipped, the condition is satisfied
         local has_equipped = false
         local items = requirements.any_equipped_item
         if type(items) == 'string' then
            items = {items}
         end

         for _, item in ipairs(items) do
            if equipment_component:has_item_type(item) then
               has_equipped = true
               break
            end
         end

         if not has_equipped then
            return false
         end
      end

      if requirements.any_active_buff then
         local buffs_component = entity:get_component('stonehearth:buffs')
         if not buffs_component then
            return false
         end

         local has_buff = false
         local buffs = requirements.any_active_buff
         if type(buffs) == 'string' then
            buffs = {buffs}
         end

         for _, buff in ipairs(buffs) do
            if buffs_component:has_buff(buff) then
               has_buff = true
               break
            end
         end

         if not has_buff then
            return false
         end
      end

      return true
   end
end

function PeriodicInteractionComponent:_check_modes_for_valid_job_levels(job_uri, level)
   local has_changed = false

   for mode, data in pairs(self._json.modes) do
      if data.requirements and data.requirements.job then
         if job_uri == data.requirements.job then
            local had_eligible_job = self._sv.ui_data[mode].has_eligible_job
            local has_eligible_job = level >= (data.requirements.level or 1)

            if has_eligible_job ~= had_eligible_job then
               has_changed = true
               self._sv.ui_data[mode].has_eligible_job = has_eligible_job
            end
         end
      end
   end

   if has_changed then
      self.__saved_variables:mark_changed()
   end
end

function PeriodicInteractionComponent:get_current_interaction()
   return self._current_sequence_data and self._current_sequence_data[self._sv.interaction_stage]
end

function PeriodicInteractionComponent:get_interaction_point(point_id)
   return self._json.interaction_points and self._json.interaction_points[point_id]
end

function PeriodicInteractionComponent:select_finish_stage_command(session, response, index)
   self:set_finish_stage(index)
   return true
end

function PeriodicInteractionComponent:set_finish_stage(index)
   self._sv.finish_stage = math.min(index, self._current_sequence_data and #self._current_sequence_data or 1)
   self.__saved_variables:mark_changed()
   self:_consider_usability()
end

function PeriodicInteractionComponent:set_ingredient_quality(quality)
   self._sv.ingredient_quality = quality
   self.__saved_variables:mark_changed()
end

function PeriodicInteractionComponent:set_current_interaction_completed(user)
   self._sv.current_user = user
   self:_create_current_user_job_listener()

   local current_interaction = self:get_current_interaction()
   if not current_interaction then
      return
   end

   -- if the finish stage has been set to this stage, we want to complete now
   local completed = self._sv.interaction_stage >= self._sv.finish_stage

   -- apply any rewards
   local item
   completed, item = self:_apply_rewards(completed and current_interaction.finish_rewards or current_interaction.rewards, completed)

   local user_event = user and current_interaction.user_event
   if user_event and user_event.event then
      local args = {
         user = user,
         item = item,
      }
      if user_event.user_entity then
         args[user_event.user_entity] = user
      end
      if user_event.item_spawned then
         args[user_event.item_spawned] = item
      end
      radiant.events[user_event.sync and 'trigger' or 'trigger_async'](self._entity, user_event.event, args)
   end
   
   -- if this was the first interaction for this sequence, start the general cooldown
   if self._sv.interaction_stage == 1 and self._current_mode_data.cooldown then
      self:_start_general_cooldown_timer(self._current_mode_data.cooldown)
   end

   if completed then
      self:_reset(true)
   else
      self:_move_to_next_stage()
   end
end

function PeriodicInteractionComponent:_move_to_next_stage()
   local current_interaction = self:get_current_interaction()
   if not current_interaction then
      return
   end
   self:_start_interaction_cooldown_timer(current_interaction.cooldown)
   self._sv.interaction_stage = self._sv.interaction_stage + 1
   self.__saved_variables:mark_changed()

   current_interaction = self:get_current_interaction()
   if not current_interaction then
      -- if there's no interaction for this stage, we must've completed it
      self:_reset(true)
   else
      self:_apply_current_stage_settings()
      self:_consider_usability()
   end
end

function PeriodicInteractionComponent:_apply_current_stage_settings()
   local current_interaction = self:get_current_interaction()
   if current_interaction then
      log:debug('%s applying stage settings for %s...', self._entity, self._sv.interaction_stage)
      -- apply model/effect, etc.
      if current_interaction.model then
         self._entity:add_component('render_info'):set_model_variant(current_interaction.model)
      end
      if current_interaction.effect then
         self:_set_interaction_stage_effect(current_interaction.effect)
      end
      self:_start_evolve_timer(current_interaction.evolve)
   end
end

function PeriodicInteractionComponent:_set_interaction_stage_effect(effect)
   if self._interaction_stage_effect then
      self._interaction_stage_effect:stop()
      self._interaction_stage_effect = nil
   end

   if effect then
      self._interaction_stage_effect = radiant.effects.run_effect(self._entity, effect)
   end
end

function PeriodicInteractionComponent:set_interaction_effect(effect)
   if self._interaction_effect then
      self._interaction_effect:stop()
      self._interaction_effect = nil
   end

   if effect then
      self._interaction_effect = radiant.effects.run_effect(self._entity, effect)
   end
end

function PeriodicInteractionComponent:_apply_rewards(rewards, is_completed)
   local user = self._sv.current_user
   if not rewards or not user or not user:is_valid() then
      -- can't apply a reward without rewards or a recipient!
      log:error('%s cannot apply rewards for user %s', self._entity, tostring(user))
      return is_completed
   end

   local completed = is_completed
   local item_spawned

   for _, reward in ipairs(rewards) do
      local this_completed, this_item_spawned = self:_apply_reward(reward, is_completed)
      completed = completed or this_completed
      item_spawned = item_spawned or this_item_spawned
   end

   return completed, item_spawned
end

-- different types of rewards: user_buff, self_buff, experience, permanent_attribute, expendable_resource, script
function PeriodicInteractionComponent:_apply_reward(reward, is_completed)
   local user = self._sv.current_user
   local spawned_item
   
   if reward.type == 'user_buff' then
      user:add_component('stonehearth:buffs'):add_buff(reward.buff)
   elseif reward.type == 'self_buff' then
      self._entity:add_component('stonehearth:buffs'):add_buff(reward.buff)
   elseif reward.type == 'experience' then
      local job_component = user:get_component('stonehearth:job')
      if job_component then
         local level = job_component:get_current_job_level()
         job_component:add_exp(reward.value)
         if reward.levelup_triggers_completion and level < job_component:get_current_job_level() then
            return true
         end
      end
   elseif reward.type == 'permanent_attribute' then
      local attributes_component = user:add_component('stonehearth:attributes')
      local cur_value = attributes_component:get_attribute(reward.attribute)
      attributes_component:set_attribute(reward.attribute, cur_value + reward.amount or 1)
   elseif reward.type == 'expendable_resource' then
      local expendable_resources_component = user:add_component('stonehearth:expendable_resources')
      if reward.maximize then
         expendable_resources_component:set_value(reward.resource, expendable_resources_component:get_max_value(reward.resource))
      elseif reward.minimize then
         expendable_resources_component:set_value(reward.resource, expendable_resources_component:get_min_value(reward.resource))
      else
         local cur_value = expendable_resources_component:get_value(reward.resource)
         expendable_resources_component:set_value(reward.resource, cur_value + reward.amount or 0)
      end
   elseif reward.type == 'craft_items' and user then
      -- use this item's quality if no ingredient quality was provided
      -- determine the quality for each item to spawn
      local ingredient_quality = self._sv.ingredient_quality or radiant.entities.get_item_quality(self._entity)
      local quality_table = item_quality_lib.get_quality_table(user, reward.category, ingredient_quality)
      local uris = {}
      for uri, quantity in pairs(reward.items) do
         if type(quantity) == 'table' then
            quantity = rng:get_int(quantity.min, quantity.max)
         end
         if quantity > 0 then
            local uri_table = {}
            for i = 1, quantity do
               local quality = item_quality_lib.get_quality(quality_table)
               uri_table[quality] = (uri_table[quality] or 0) + 1
            end
            uris[uri] = uri_table
         end
      end

      local options = {
         owner = user:get_player_id(),
         inputs = user,
         output = self._entity,
         spill_fail_items = true,
         --add_spilled_to_inventory = true,
      }

      local location = radiant.entities.get_world_grid_location(user) or radiant.entities.get_world_grid_location(self._entity)
      local items = radiant.entities.get_successfully_output_items(radiant.entities.output_items(uris, location, 0, 4, options))
      local event_args = {recipe_data = reward}
      if next(items) then
         spawned_item = items[next(items)]
         event_args.product = spawned_item
         event_args.product_uri = spawned_item:get_uri()
      end

      -- if we're "crafting" something, make sure that gets communicated to the crafter
      -- reward should specify level_requirement, category, and proficiency_gain fields if relevant
      radiant.events.trigger_async(user, 'stonehearth:crafter:craft_item', event_args)
   elseif reward.type == 'spawn_items' then
      -- use this item's quality (as if it were an rn/rrn)
      local quality = radiant.entities.get_item_quality(self._entity)
      local uris = {}
      for uri, quantity in pairs(reward.items) do
         if type(quantity) == 'table' then
            quantity = rng:get_int(quantity.min, quantity.max)
         end
         if quantity > 0 then
            uris[uri] = {[quality] = quantity}
         end
      end

      local options = {
         owner = user and user:get_player_id() or self._entity:get_player_id(),
         inputs = user,
         output = self._entity,
         spill_fail_items = true,
         --add_spilled_to_inventory = true,
      }

      local location = user and radiant.entities.get_world_grid_location(user) or radiant.entities.get_world_grid_location(self._entity)
      local items = radiant.entities.get_successfully_output_items(radiant.entities.output_items(uris, location, 0, 4, options))
      if next(items) then
         spawned_item = items[next(items)]
      end
   elseif reward.type == 'script' then
      local script = radiant.mods.load_script(reward.script)
      if script and script.process_reward then
         return script.process_reward(self._entity, user, self._sv.interaction_stage, reward.script_data, is_completed)
      end
   end

   return false, spawned_item
end

function PeriodicInteractionComponent:_start_general_cooldown_timer(duration)
   if not self._sv._general_cooldown_timer and duration then
      self._sv._general_cooldown_timer = stonehearth.calendar:set_persistent_timer("PeriodicInteraction general",
            duration, radiant.bind(self, '_general_cooldown_finished'))
   end
end

function PeriodicInteractionComponent:_start_interaction_cooldown_timer(duration)
   if not self._sv._interaction_cooldown_timer and duration then
      log:debug('%s setting interaction cooldown for %s of %s...', self._entity, self._sv.interaction_stage, duration)
      self._sv._interaction_cooldown_timer = stonehearth.calendar:set_persistent_timer("PeriodicInteraction interaction",
            duration, radiant.bind(self, '_interaction_cooldown_finished'))
   end
end

function PeriodicInteractionComponent:_start_evolve_timer(duration)
   if not self._sv._evolve_timer and duration then
      log:debug('%s setting evolve timer for %s of %s...', self._entity, self._sv.interaction_stage, duration)
      self._sv._evolve_timer = stonehearth.calendar:set_persistent_timer("PeriodicInteraction evolve",
            duration, radiant.bind(self, '_evolve_finished'))
   end
end

function PeriodicInteractionComponent:_stop_evolve_timer()
   if self._sv._evolve_timer then
      self._sv._evolve_timer:destroy()
      self._sv._evolve_timer = nil
   end
end

function PeriodicInteractionComponent:_stop_interaction_cooldown_timer()
   if self._sv._interaction_cooldown_timer then
      self._sv._interaction_cooldown_timer:destroy()
      self._sv._interaction_cooldown_timer = nil
   end
end

function PeriodicInteractionComponent:_stop_general_cooldown_timer()
   if self._sv._general_cooldown_timer then
      self._sv._general_cooldown_timer:destroy()
      self._sv._general_cooldown_timer = nil
   end
end

function PeriodicInteractionComponent:_general_cooldown_finished()
   self:_stop_general_cooldown_timer()

   self:_consider_usability()
end

function PeriodicInteractionComponent:_interaction_cooldown_finished()
   self:_stop_interaction_cooldown_timer()

   self:_consider_usability()
end

function PeriodicInteractionComponent:_evolve_finished()
   self:_stop_evolve_timer()

   -- proceed to the next stage regardless of enabled/interaction status
   self:_move_to_next_stage()
end

-- consider whether (and who) to alert that this entity can be interacted with
function PeriodicInteractionComponent:_consider_usability(force_reconsider)
   -- if it's not in the world, ignore this
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end

   local usable = true
   local current_interaction = self:get_current_interaction()

   -- if it's not enabled (and the sequence hasn't started yet), on general cooldown, or on interaction cooldown, we can't use it
   -- "evolve" is handled separately from actual usability
   if (not self._sv.enabled and self._sv.interaction_stage == 1) or self._sv._general_cooldown_timer or self._sv._interaction_cooldown_timer then
      usable = false
      log:debug('%s is not usable: enabled = %s, general cd = %s, interaction cd = %s', self._entity,
            tostring(self._sv.enabled), tostring(self._sv._general_cooldown_timer), tostring(self._sv._interaction_cooldown_timer))
   elseif current_interaction then
      -- if the finish stage is now or earlier, and this stage is allowed to be selected as a finish stage
      -- or if num_interactions is specified and > 0, then it's interactable
      -- so, if the finish stage is in the future or this isn't allowed to be a finish stage,
      -- and num_interactions isn't specified or is 0, it's *not* interactable
      if (current_interaction.num_interactions or 0) < 1 and (not current_interaction.allow_finish_selection or self._sv.finish_stage > self._sv.interaction_stage) then
         usable = false
         log:debug('%s is not usable: num_interactions = %s, finish stage = %s, interaction stage = %s', self._entity,
               tostring(current_interaction.num_interactions), tostring(self._sv.finish_stage), tostring(self._sv.interaction_stage))
      end
   end

   local task_tracker_component = self._entity:add_component('stonehearth:task_tracker')

   if force_reconsider or usable ~= self._is_usable then
      self._is_usable = usable
      --stonehearth.ai:reconsider_entity(self._entity, 'stonehearth_ace:periodic_interaction')
      log:debug('%s _consider_usability (%s) => reconsider_entity', self._entity, usable)

      if self._is_usable then
         -- if the task is already created, no need to cancel and recreate it unless we're doing a force reconsider
         -- which happens on load and when the mode is changed (which can change the ingredient for an interaction)
         -- however, we do want to update the overlay effect in case that's different
         local was_requested = task_tracker_component:is_activity_requested(PI_ACTION) or
               task_tracker_component:is_activity_requested(PI_WITH_INGREDIENT_ACTION)
         if was_requested then
            task_tracker_component:cancel_current_task(false)
         end

         local action = self:_get_interaction_action(current_interaction)
         task_tracker_component:request_task(self._entity:get_player_id(), 'periodic_interaction', action, current_interaction.overlay_effect)

         -- if it hadn't been requested before, or if we're forcing reconsider, destroy/recreate the tasks
         if force_reconsider or not was_requested then
            self:_create_interaction_tasks(current_interaction)
         end
      else
         self:_destroy_interaction_tasks()
         local was_requested = task_tracker_component:is_activity_requested(PI_ACTION) or
               task_tracker_component:is_activity_requested(PI_WITH_INGREDIENT_ACTION)
         if was_requested then
            task_tracker_component:cancel_current_task(false)
         end
      end
   else
      log:debug('%s _consider_usability (%s)', self._entity, usable)
   end
end

function PeriodicInteractionComponent:_get_interaction_action(data)
   if data and (data.ingredient_uri or data.ingredient_material) then
      return PI_WITH_INGREDIENT_ACTION
   else
      return PI_ACTION
   end
end

function PeriodicInteractionComponent:_get_interaction_ingredient(data)
   local ingredient
   if data.ingredient_uri then
      ingredient = {uri = data.ingredient_uri}
   elseif data.ingredient_material then
      ingredient = {material = data.ingredient_material}
   end
   return ingredient
end

function PeriodicInteractionComponent:_create_interaction_tasks(data)
   self:_destroy_interaction_tasks()

   local player_id = self._entity:get_player_id()
   local town = stonehearth.town:get_town(player_id)

   if town and town:get_task_group(PI_TASK_GROUP) then
      local args = {
         item = self._entity,
         ingredient = self:_get_interaction_ingredient(data)
      }

      local interaction_task = town:create_task_for_group(
         PI_TASK_GROUP,
         self:_get_interaction_action(data),
         args)
            :set_source(self._entity)
            :start()
      table.insert(self._added_interaction_tasks, interaction_task)
   elseif town then
      log:debug('cannot create transform task for %s: town "%s" doesn\'t exist or has no transform task group', self._entity, player_id)
   end
end

function PeriodicInteractionComponent:_destroy_interaction_tasks()
   if self._added_interaction_tasks then
      for _, task in ipairs(self._added_interaction_tasks) do
         task:destroy()
      end
   end
   self._added_interaction_tasks = {}
end

return PeriodicInteractionComponent
