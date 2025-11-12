local Entity = _radiant.om.Entity

local AttackSummonPathToTarget = radiant.class()

AttackSummonPathToTarget.name = 'attack summon path to target'
AttackSummonPathToTarget.does = 'stonehearth:combat:attack'
AttackSummonPathToTarget.args = {
   target = Entity
}
AttackSummonPathToTarget.priority = 0.2
AttackSummonPathToTarget.weight = 1

local ai = stonehearth.ai
return ai:create_compound_action(AttackSummonPathToTarget)
   :execute('stonehearth:combat:abort_on_leash_changed')
   :execute('stonehearth:combat:chase_entity_until_targetable', {
      target = ai.ARGS.target,
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('stonehearth_ace:combat:attack_summon', {
      target = ai.ARGS.target,
   })
