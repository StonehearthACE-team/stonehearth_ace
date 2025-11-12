local Entity = _radiant.om.Entity

local AttackSummonMoveToLOS = radiant.class()

AttackSummonMoveToLOS.name = 'attack summon move to targetable location'
AttackSummonMoveToLOS.does = 'stonehearth:combat:attack'
AttackSummonMoveToLOS.args = {
   target = Entity
}
AttackSummonMoveToLOS.priority = 0.3
AttackSummonMoveToLOS.weight = 1

local ai = stonehearth.ai
return ai:create_compound_action(AttackSummonMoveToLOS)
   :execute('stonehearth:combat:abort_on_leash_changed')
   :execute('stonehearth:combat:move_to_targetable_location', {
      target = ai.ARGS.target,
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('stonehearth_ace:combat:attack_summon', {
      target = ai.ARGS.target,
   })
