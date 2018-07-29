local Entity = _radiant.om.Entity
local TrainAttack = class()

TrainAttack.name = 'training attack'
--TrainAttack.status_text_key = 'stonehearth_ace:ai.actions.status_text.train'
TrainAttack.does = 'stonehearth_ace:train_attack'
TrainAttack.args = { target = Entity }
TrainAttack.priority = 0

local log = radiant.log.create_logger('training_action')

function TrainAttack:start_thinking(ai, entity, args)
	local check_conditions = self:_check_conditions(ai, entity, args)
	if check_conditions then
		ai:reject(check_conditions)
		return
	end
	
	ai:set_think_output()
end

function TrainAttack:start(ai, entity, args)
	local check_conditions = self:_check_conditions(ai, entity, args)
	if check_conditions then
		ai:abort(check_conditions)
		return
	end
end

function TrainAttack:_check_conditions(ai, entity, args)
	-- make sure the target is a training dummy
	local dummy = args.target and args.target:get_component('stonehearth_ace:training_dummy')
	if not dummy then
		return 'target is not a valid training dummy'
	end
	local health = args.target:get_component('stonehearth:expendable_resources'):get_value('health')
	if not health or health <= 0 then
		return 'training dummy target is already dead'
	end

	local job = entity:get_component('stonehearth:job')
	if job:is_max_level() then
		return 'entity is max level, cannot train'
	end
	
	if not job:get_training_enabled() then
		return 'training is disabled or unavailable for this entity'
	end

	return nil
end

function TrainAttack:run(ai, entity, args)
	ai:execute('stonehearth:combat:attack', { target = args.target })
	radiant.events.trigger_async(entity, 'stonehearth_ace:training_performed')
end

return TrainAttack
