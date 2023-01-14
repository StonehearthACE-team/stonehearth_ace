local Entity = _radiant.om.Entity
local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'

local HealEntityAdjacentWithMagic = radiant.class()
HealEntityAdjacentWithMagic.name = 'magically heal entity adjacent'
HealEntityAdjacentWithMagic.does = 'stonehearth_ace:heal_entity_adjacent_with_magic'
HealEntityAdjacentWithMagic.args = {
   container = Entity,   -- the container the entity is in
}
HealEntityAdjacentWithMagic.priority = 0

local log = radiant.log.create_logger('stonehearth_ace:heal_entity_adjacent_with_magic')

function HealEntityAdjacentWithMagic:run(ai, entity, args)
   local injured_entity = nil
   if args.container == entity then
      injured_entity = entity
   else
      local container_user = args.container:get_component('stonehearth:mount'):get_user()
      if container_user and radiant.entities.has_buff(container_user, 'stonehearth:buffs:hidden:needs_medical_attention') and
            not radiant.entities.has_buff(container_user, 'stonehearth_ace:buffs:recently_magically_treated') then
         injured_entity = container_user
      end
   end

   if not injured_entity then
      ai:abort('no injured entity needs healing')
      return
   end

   ai:set_status_text_key('stonehearth:ai.actions.status_text.healing_target', { target = injured_entity })
   local job = entity:get_component('stonehearth:job')
   local medic_capabilities = job and job:get_curr_job_controller():get_medic_capabilities()

   local heal_cast_time = medic_capabilities.time_to_impact or stonehearth.constants.effect_times.SINGLE_TARGET_HEAL_CAST_TIME
	local in_progress_heal_cast_effect = medic_capabilities.in_progress_heal_cast_effect or stonehearth.constants.effects.IN_PROGRESS_HEAL_CAST
   local in_progress_heal_effect = medic_capabilities.in_progress_heal_effect or stonehearth.constants.effects.IN_PROGRESS_HEAL
   local cast_effect = medic_capabilities.cast_effect or stonehearth.constants.effects.CAST_HEAL
   local target_effect = medic_capabilities.target_effect or stonehearth.constants.effects.SINGLE_TARGET_HEAL
   
   self._in_progress_heal_cast = radiant.effects.run_effect(entity, in_progress_heal_cast_effect)
   self._in_progress_heal = radiant.effects.run_effect(injured_entity, in_progress_heal_effect)

   self._heal_impact_timer = stonehearth.combat:set_timer("magic medic do heal", heal_cast_time,
      function ()
         log:debug('heal_impact_timer hit')
         if not entity:is_valid() or not injured_entity:is_valid() then
            return
         end

         radiant.effects.run_effect(injured_entity, target_effect)

         self:_heal(entity, injured_entity, medic_capabilities)
      end
   )

   ai:execute('stonehearth:run_effect', { effect = cast_effect })

   radiant.events.trigger_async(entity, 'stonehearth:repaired_entity', { entity = injured_entity })
   radiant.events.trigger_async(injured_entity, 'stonehearth_ace:entity:magically_healed', { healer = entity })
end

function HealEntityAdjacentWithMagic:stop(ai, entity, args)
   if self._heal_impact_timer then
      -- cancel the timer if we were pre-empted
      self._heal_impact_timer:destroy()
      self._heal_impact_timer = nil
   end
   self:destroy_heal_effect()
end

function HealEntityAdjacentWithMagic:destroy_heal_effect()
   if self._in_progress_heal then
      self._in_progress_heal:stop()
      self._in_progress_heal = nil
   end
   if self._in_progress_heal_cast then
      self._in_progress_heal_cast:stop()
      self._in_progress_heal_cast = nil
   end
end

function HealEntityAdjacentWithMagic:_heal(healer, target, medic_capabilities)
   log:debug('%s performing _heal on %s', healer, target)
   
   if not target:is_valid() then
      return
   end

   -- remove X number of the top priority treatable conditions
   for i = 1, medic_capabilities.num_conditions_to_cure or 1 do
      local conditions = healing_lib.get_conditions_needing_cure(target)
      if not next(conditions) then
         break
      end

      -- go through until we have something we can treat
      if medic_capabilities.cure_conditions then
         for _, condition in ipairs(conditions) do
            local cure_rank = medic_capabilities.cure_conditions[condition.condition]
            if cure_rank then
               log:debug('%s curing condition %s (rank %s) on %s', healer, condition.condition, cure_rank, target)
               healing_lib.cure_conditions(target, {[condition.condition] = cure_rank})
               break
            end
         end
      end
   end

   healing_lib.heal_target(healer, target, medic_capabilities.health_healed or 1, medic_capabilities.guts_healed)

	if medic_capabilities.apply_buff then
		radiant.entities.add_buff(target, medic_capabilities.apply_buff, {
         source = healer,
         source_player = radiant.entities.get_player_id(healer),
      })
   end
   
   -- set this ability on cooldown
   local cooldown = medic_capabilities.cooldown or '12h'
   if not radiant.util.is_number(cooldown) then
      cooldown = stonehearth.calendar:debug_game_seconds_to_realtime(stonehearth.calendar:parse_duration(medic_capabilities.cooldown), true)
   end
   local combat_state = healer:add_component('stonehearth:combat_state')
   combat_state:start_cooldown('stonehearth_ace:magic_medic', cooldown)

   radiant.events.trigger_async(healer, 'stonehearth:healer:healed_entity', { entity = target })
end

return HealEntityAdjacentWithMagic
