local Entity = _radiant.om.Entity
local TrainAttackMoveToTargetableLocation = class()

TrainAttackMoveToTargetableLocation.name = 'train attack move to targetable location'
TrainAttackMoveToTargetableLocation.does = 'stonehearth_ace:train_attack'
TrainAttackMoveToTargetableLocation.args = {
	target = Entity
}
TrainAttackMoveToTargetableLocation.priority = 0.5

local ai = stonehearth.ai
return ai:create_compound_action(TrainAttackMoveToTargetableLocation)
		:execute('stonehearth_ace:train_move_to_targetable_location', {
			target = ai.ARGS.target,
		})
      :execute('stonehearth_ace:train_between_attacks', { target = ai.ARGS.target })
		:execute('stonehearth_ace:train_attack_adjacent', { target = ai.ARGS.target })
