--[[
   ACE: overriding because combat classes mixin to this class, similar to BaseJob
   adding support for issue_party_commands_when_job_disabled gameplay setting with existing combat class work_order_status listener
]]

-- Base class for all crafting jobs.
local constants = require 'stonehearth.constants'
local BaseJob = require 'stonehearth.jobs.base_job'

local CombatJob = class()
radiant.mixin(CombatJob, BaseJob)

local JOB_WORK_ORDER_NAME = 'job'
local JOB_DISABLED_STANCE = 'defensive'

function CombatJob:initialize()
   BaseJob.initialize(self)
   self._sv._accumulated_town_protection_time = 0
end

function CombatJob:activate()
   BaseJob.activate(self)
   self._sv.is_combat_class = true
end

function CombatJob:post_activate()
   if self._sv.is_current_class then
      self:_on_work_order_changed()
   end
end

function CombatJob:promote(json_path, options)
   BaseJob.promote(self, json_path)
   --consider making a combat class base class, like crafters
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local population = stonehearth.population:get_population(player_id)
   local curr_party = stonehearth.unit_control:get_party_for_entity_command({}, {}, self._sv._entity)
   if not curr_party then
      --get the red party
      curr_party = population:get_party_by_name('party_1')
      if curr_party then -- npcs might not have party
         local party_component = curr_party:get_component('stonehearth:party')
         if party_component then
            party_component:add_member(self._sv._entity)
         end
      end
   end
end

--Add or remove a type of combat action the archer can choose in melee
function CombatJob:add_combat_action(args)
   BaseJob.add_equipment(self, args)
   local combat_state = stonehearth.combat:get_combat_state(self._sv._entity)
   combat_state:recompile_combat_actions(args.action_type)
end

function CombatJob:add_chained_combat_action(args)
   BaseJob.apply_chained_equipment(self, args)
   local combat_state = stonehearth.combat:get_combat_state(self._sv._entity)
   combat_state:recompile_combat_actions(args.action_type)
end

function CombatJob:remove_combat_action(args)
   BaseJob.remove_equipment(self, args)
   local combat_state = stonehearth.combat:get_combat_state(self._sv._entity)
   combat_state:recompile_combat_actions(args.action_type)
end

-- if args is specified, it's being called by the event
function CombatJob:_on_work_order_changed(args)
   local job_changed = args and args.work_order_name == JOB_WORK_ORDER_NAME
   local work_order_component = self._sv._entity:get_component('stonehearth:work_order')
   if work_order_component then
      local job_enabled = work_order_component:is_work_order_enabled(JOB_WORK_ORDER_NAME)
      if job_enabled then
         self._job_component:reset_to_default_combat_stance()
      else
         stonehearth.combat:set_stance(self._sv._entity, JOB_DISABLED_STANCE)
      end

      -- apply/cancel party commands if relevant
      if job_changed then
         stonehearth.combat_server_commands:reconsider_individual_party_commands(self._sv._entity, job_enabled)
      end
   end
end

function CombatJob:_on_town_protection_completed(e)
   local xp_to_add = self._xp_rewards["town_protection"]
   if not xp_to_add then
      return
   end

   local new_duration = self._sv._accumulated_town_protection_time + e.duration
   while new_duration > stonehearth.constants.town_protection.SECS_FOR_XP_GAIN do
      self._job_component:add_exp(xp_to_add, false) -- no curiosity addition for patrolling/defending location. makes it too OP
      new_duration = new_duration - stonehearth.constants.town_protection.SECS_FOR_XP_GAIN
   end
   self._sv._accumulated_town_protection_time = new_duration
end

function CombatJob:_create_listeners()
   self._work_order_status_changed = radiant.events.listen(self._sv._entity, 'stonehearth:work_order:status_changed', self, self._on_work_order_changed)

   if self._xp_rewards["town_protection"] then
      self._patrol_listener = radiant.events.listen(self._sv._entity, 'stonehearth:town_protection_completed', self, self._on_town_protection_completed)
   end
end

function CombatJob:_remove_listeners()
   if self._work_order_status_changed then
      self._work_order_status_changed:destroy()
      self._work_order_status_changed = nil
   end

   if self._patrol_listener then
      self._patrol_listener:destroy()
      self._patrol_listener = nil
   end
end

return CombatJob
