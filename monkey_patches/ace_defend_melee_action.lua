local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('combat')

local AceDefendMelee = class()

function AceDefendMelee:run(ai, entity, args)
   -- make sure the assault is still incoming
   if not self._assault_context.assault_active then
      log:info('assault on %s was cancelled', entity)
      ai:abort('assault was cancelled')
   end

   -- make sure we still have time to defend
   local defend_start_delay = self:_get_defend_start_delay(self._assault_context, self._defend_info)

   if defend_start_delay < 0 then
      log:warning('%s DefendMelee could not run in time', entity)
      ai:abort('DefendMelee could not run in time')
   end

   stonehearth.combat:start_cooldown(entity, self._defend_info)

   -- roll if defense action was successful
   if not self:_roll_success(entity, self._defend_info) then
      return
   end

   -- ACE: also apply any self buffs, if defined
   stonehearth.combat:apply_buffs(entity, entity, self._defend_info)

   stonehearth.combat:begin_defense(self._assault_context)

   radiant.entities.turn_to_face(entity, self._assault_context.attacker)

   ai:execute('stonehearth:run_effect', {
      effect = self._defend_info.effect,
      delay = defend_start_delay
   })

   stonehearth.combat:end_defense(self._assault_context)
   self._assault_context = nil
end

return AceDefendMelee
