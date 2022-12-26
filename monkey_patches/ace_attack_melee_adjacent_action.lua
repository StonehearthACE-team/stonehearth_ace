local AssaultContext = require 'stonehearth.services.server.combat.assault_context'
local BatteryContext = require 'stonehearth.services.server.combat.battery_context'
local log = radiant.log.create_logger('combat')

local AceAttackMeleeAdjacent = radiant.class()

function AceAttackMeleeAdjacent:run(ai, entity, args)
   local target = args.target
   ai:set_status_text_key('stonehearth:ai.actions.status_text.attack_melee_adjacent', { target = target })

   local weapon = stonehearth.combat:get_main_weapon(entity)
   if not weapon or not weapon:is_valid() then
      log:warning('%s no longer has a valid weapon', entity)
      ai:abort('Attacker no longer has a valid weapon')
   end

   local weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
   assert(weapon_data)

   local melee_range_ideal, melee_range_max = stonehearth.combat:get_melee_range(entity, weapon_data, target)
   local distance = radiant.entities.distance_between(entity, target)
   if distance > melee_range_max then
      log:warning('%s unable to get within maximum melee range (%f) of %s', entity, melee_range_max, target)
      ai:abort('Target out of melee range')
      return
   end

   if args.face_target then
      radiant.entities.turn_to_face(entity, target)
   end

   ai:execute('stonehearth:bump_against_entity', { entity = target, distance = melee_range_ideal })

   stonehearth.combat:start_cooldown(entity, self._attack_info)

   -- the target might die when we attack them, so unprotect now!
   ai:unprotect_argument(target)

   local impact_time = radiant.gamestate.now() + self._attack_info.time_to_impact
   self._assault_context = AssaultContext('melee', entity, target, impact_time)
   stonehearth.combat:begin_assault(self._assault_context)

   -- can't ai:execute this. it needs to run in parallel with the attack animation
   self._hit_effect = radiant.effects.run_effect(
      target, 'stonehearth:effects:hit_sparks:hit_effect', self._attack_info.time_to_impact
   )

   self._impact_timer = stonehearth.combat:set_timer("AttackMeleeAdjacent do damage", self._attack_info.time_to_impact,
      function ()
         if not entity:is_valid() or not target:is_valid() then
            return
         end

         -- local range = radiant.entities.distance_between(entity, target)
         -- local out_of_range = range > melee_range_max

         -- All attacks now hit even if the target runs out of range
         local out_of_range = false

         if out_of_range or self._assault_context.target_defending then
            self._hit_effect:stop()
            self._hit_effect = nil
         else
            -- TODO: Implement system to collect all damage types and all armor types
            -- and then resolve to compute the final damage type.
            -- TODO: figure out HP progression of enemies, so this system will scale well
            -- For example, if you melee Cthulu what elements should be in play so a high lv footman
            -- will be able to actually make a difference?
            -- For now, will have an additive dmg attribute, a multiplicative dmg attribute
            -- and will apply both to this base damage number
            -- TODO: Albert to implement more robust solution after he works on mining
            local total_damage = stonehearth.combat:calculate_melee_damage(entity, target, self._attack_info)
            local target_id = target:get_id()
            local aggro_override = stonehearth.combat:calculate_aggro_override(total_damage, self._attack_info)
            local battery_context = BatteryContext(entity, target, total_damage, aggro_override, true)

            stonehearth.combat:inflict_debuffs(entity, target, self._attack_info)
            stonehearth.combat:battery(battery_context)

            if self._attack_info.aoe_effect then
               self:_apply_aoe_damage(entity, target_id, melee_range_max, self._attack_info)
            end
         end
      end
   )

   ai:execute('stonehearth:run_effect', { effect = self._attack_info.effect })

   stonehearth.combat:end_assault(self._assault_context)
   self._assault_context = nil
end

return AceAttackMeleeAdjacent
