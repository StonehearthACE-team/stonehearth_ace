local Entity = _radiant.om.Entity
local TrainAttackFromCurrentLocation = class()

TrainAttackFromCurrentLocation.name = 'train attack from current location'
TrainAttackFromCurrentLocation.does = 'stonehearth_ace:train_attack'
TrainAttackFromCurrentLocation.args = {
	target = Entity
}
TrainAttackFromCurrentLocation.priority = 1

local ai = stonehearth.ai
return ai:create_compound_action(TrainAttackFromCurrentLocation)
		:execute('stonehearth_ace:train_check_entity_targetable', {
			target = ai.ARGS.target,
		})
		:execute('stonehearth:combat:wait_for_global_attack_cooldown')
		:execute('stonehearth:bump_allies', {
			distance = 2,
		})
		:execute('stonehearth_ace:train_attack_adjacent', { target = ai.ARGS.target })
		:execute('stonehearth:combat:set_global_attack_cooldown')
