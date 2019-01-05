local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local TrainCheckEntityTargetable = class()

TrainCheckEntityTargetable.name = 'train check entity targetable'
TrainCheckEntityTargetable.does = 'stonehearth_ace:train_check_entity_targetable'
TrainCheckEntityTargetable.args = {
	target = Entity
}
TrainCheckEntityTargetable.priority = 0.5

local log = radiant.log.create_logger('training_action')
local combat = stonehearth.combat

function TrainCheckEntityTargetable:start_thinking(ai, entity, args)
 
	if is_entity_infront_of_target(entity, args.target) then
		ai:set_think_output()
	else
		ai:clear_think_output()
	end
end

function is_entity_infront_of_target(entity, target)
	-- determine if entity is in weapon range
	local weapon = combat:get_main_weapon(entity)
	local weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
	if weapon_data.range then
		-- it's a ranged combat class so get the range including any bonus range
		if not stonehearth.combat:in_range_and_has_line_of_sight(entity, target, weapon) then
			return false
		end
	else
		-- otherwise it's melee so get the reach
		local melee_range_ideal, melee_range_max = stonehearth.combat:get_melee_range(entity, weapon_data, target)
		local distance = radiant.entities.distance_between(entity, target)
		if distance > melee_range_max then
			return false
		end
	end
	-- determine if current position is infront of the target
	local mob = target:get_component('mob')
	local facing = radiant.math.round(mob:get_facing() / 90) * 90
	local facing_vector = radiant.math.rotate_about_y_axis(-Point3.unit_z, facing):to_closest_int()
	local entity_location = radiant.entities.get_location(entity)
	local target_location = mob:get_world_grid_location()
	local target_to_entity_vector = entity_location - target_location
	target_to_entity_vector:normalize()

	if math.acos(facing_vector:dot(target_to_entity_vector)) <= math.rad(90) then
		return true
	else
		return false
	end
end

function get_location_in_front(location, facing, distance)
	local offset = radiant.math.rotate_about_y_axis(-Point3(0, 0, distance), facing)
	return location + offset
end

return TrainCheckEntityTargetable