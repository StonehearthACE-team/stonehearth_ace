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
	if not dummy or not dummy:get_enabled() then
		return 'target is not a valid/enabled training dummy'
	end

	local health = args.target:get_component('stonehearth:expendable_resources'):get_value('health')
	if not health or health <= 0 then
		return 'training dummy target is already dead'
	end

	local job = entity:get_component('stonehearth:job')
	if not job:is_trainable() then
		return 'entity cannot train'
	end
	
	if not job:get_training_enabled() then
		return 'training is disabled or unavailable for this entity'
	end

	local weapon = stonehearth.combat:get_main_weapon(entity)
	if not weapon or not radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data') then
		return 'entity has no weapon equipped'
	end

	return nil
end

function TrainAttack:run(ai, entity, args)
	local dummy = args.target and args.target:get_component('stonehearth_ace:training_dummy')
	if not dummy or not dummy:get_enabled() then
		ai:abort('dummy has been disabled')
		return
	end

	-- first tell the training dummy that it's "in combat"
	dummy:set_in_combat()
	
	-- check if it's a healer class do a heal action instead of attacking
	-- if it's a ranged class, attack from range
	--if entity:get_component('stonehearth:job'):has_ai_pack('stonehearth:ai_pack:healing_combat') then
	local heal_types = stonehearth.combat:get_combat_actions(entity, 'stonehearth:combat:healing_spells')
	if next(heal_types) then
		--ai:execute('stonehearth:combat:execute_heal', { target = args.target })
		radiant.entities.turn_to_face(entity, args.target)
		
		local heal_info = stonehearth.combat:choose_attack_action(entity, heal_types)
		if heal_info and heal_info.effect then
			ai:execute('stonehearth:run_effect', { effect = heal_info.effect })
		end

	elseif radiant.entities.get_entity_data(stonehearth.combat:get_main_weapon(entity), 'stonehearth:combat:weapon_data').range then
		ai:execute('stonehearth:combat:attack_ranged', { target = args.target })
	else
		ai:execute('stonehearth:combat:attack', { target = args.target })
	end

	radiant.events.trigger_async(entity, 'stonehearth_ace:training_performed')
end

return TrainAttack
