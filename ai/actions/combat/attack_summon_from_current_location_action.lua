local Entity = _radiant.om.Entity

local AttackSummonFromCurrentLocation = radiant.class()

AttackSummonFromCurrentLocation.name = 'attack summon from currrent location'
AttackSummonFromCurrentLocation.does = 'stonehearth:combat:attack'
AttackSummonFromCurrentLocation.args = {
   target = Entity
}
AttackSummonFromCurrentLocation.priority = 0.4
AttackSummonFromCurrentLocation.weight = 1

local ai = stonehearth.ai
return ai:create_compound_action(AttackSummonFromCurrentLocation)
   :execute('stonehearth:combat:check_entity_targetable', {
      target = ai.ARGS.target,
   })
   :execute('stonehearth:bump_allies', {
      distance = 2,
   })
   :execute('stonehearth_ace:combat:attack_summon', {
      target = ai.ARGS.target,
   })
