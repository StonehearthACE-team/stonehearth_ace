local HealContext = require 'stonehearth.services.server.combat.heal_context'
local constants = require 'stonehearth.constants'
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('combat')

local HealRangedInSight = radiant.class()

HealRangedInSight.name = 'heal ranged in sight'
HealRangedInSight.does = 'stonehearth:combat:execute_heal'
HealRangedInSight.args = {
   target = Entity,
}
HealRangedInSight.priority = 0

-- TODO: prohibit attacking at melee range
function HealRangedInSight:start_thinking(ai, entity, args)
   -- if the target is bedridden we don't want to do a ranged heal
   if radiant.entities.has_buff(args.target, 'stonehearth:buffs:hidden:needs_medical_attention') then
      return
   end

   local weapon = stonehearth.combat:get_main_weapon(entity)

   if not weapon or not weapon:is_valid() then
      return
   end

   self._weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:healing_data')

   -- refetch every start_thinking as the set of actions may have changed
   self._heal_types = stonehearth.combat:get_combat_actions(entity, 'stonehearth:combat:healing_spells')

   if not next(self._heal_types) then
      -- no ranged attacks
      return
   end

   self._target_offset = Point3(0, 1, 0)

   self:_choose_heal_action(ai, entity, args)
end

function HealRangedInSight:_choose_heal_action(ai, entity, args)
   -- probably should pass target in as well
   self._heal_info = stonehearth.combat:choose_attack_action(entity, self._heal_types)

   if self._heal_info then
      ai:set_think_output()
      return true
   end

   -- choose_attack_action might have complex logic, so just wait 1 second and try again
   -- instead of trying to guess which coolodowns to track
   self._think_timer = stonehearth.combat:set_timer("HealRangedInSight waiting for cooldown", 1000, function()
         self._think_timer = nil
         self:_choose_heal_action(ai, entity, args)
      end)
end

function HealRangedInSight:stop_thinking(ai, entity, args)
   if self._think_timer then
      self._think_timer:destroy()
      self._think_timer = nil
   end

   self._heal_types = nil
end

function HealRangedInSight:run(ai, entity, args)
   local target = args.target
   ai:set_status_text_key('stonehearth:ai.actions.status_text.heal_ranged_in_sight', { target = target })

   -- should be get_ranged_weapon
   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      log:warning('%s no longer has a valid weapon', entity)
      ai:abort('Healer no longer has a valid weapon')
   end

   if not stonehearth.combat:in_range_and_has_line_of_sight(entity, target, weapon) then 
      ai:abort('Target out of heal range or not in sight')
      return
   end

   radiant.entities.turn_to_face(entity, target)

   stonehearth.combat:start_cooldown(entity, self._heal_info)
   stonehearth.combat:set_assisting(entity, true)

   -- the target might die when we attack them, so unprotect now!
   ai:unprotect_argument(target)

   local heal_cast_time = self._heal_info.time_to_impact
	-- ACE additions:
	local in_progress_heal_cast_effect = self._heal_info.in_progress_heal_cast_effect or stonehearth.constants.effects.IN_PROGRESS_HEAL_CAST
	local in_progress_heal_effect = self._heal_info.in_progress_heal_effect or stonehearth.constants.effects.IN_PROGRESS_HEAL
	local target_effect = self._heal_info.target_effect or stonehearth.constants.effects.SINGLE_TARGET_HEAL
	-- End of ACE additions
   self._in_progress_heal_cast = radiant.effects.run_effect(entity, in_progress_heal_cast_effect)
   self._in_progress_heal = radiant.effects.run_effect(target, in_progress_heal_effect)

   self._heal_impact_timer = stonehearth.combat:set_timer("HealRangedInSight do heal", heal_cast_time,
      function ()
         if not entity:is_valid() or not target:is_valid() then
            return
         end

         radiant.effects.run_effect(target, target_effect)

         self:_heal(entity, target, self._weapon_data)
      end
   )

   ai:execute('stonehearth:run_effect', { effect = self._heal_info.effect })
end

function HealRangedInSight:stop(ai, entity, args)
   if self._heal_impact_timer then
      -- cancel the timer if we were pre-empted
      self._heal_impact_timer:destroy()
      self._heal_impact_timer = nil
   end
   self:destroy_heal_effect()
   self._heal_info = nil
   stonehearth.combat:set_assisting(entity, false)
end

function HealRangedInSight:destroy_heal_effect()
   if self._in_progress_heal then
      self._in_progress_heal:stop()
      self._in_progress_heal = nil
   end
   if self._in_progress_heal_cast then
      self._in_progress_heal_cast:stop()
      self._in_progress_heal_cast = nil
   end
end

function HealRangedInSight:_heal(healer, target, weapon_data)
   if not target:is_valid() then
      return
   end

   local heal_info = self._heal_info
   local total_healing = stonehearth.combat:calculate_healing(healer, target, heal_info)
   local heal_context = HealContext(healer, target, total_healing)
	
	-- ACE addition
	if heal_info.buff then
		radiant.entities.add_buff(target, heal_info.buff)
	end

   if stonehearth.combat:heal(heal_context) then
      radiant.events.trigger_async(healer, 'stonehearth:healer:healed_entity_in_combat', { entity = target })
   end
end

function HealRangedInSight:_get_target_point(target)
   local target_location = target:add_component('mob'):get_world_location()
   local target_point = target_location + self._target_offset
   return target_point
end

return HealRangedInSight
