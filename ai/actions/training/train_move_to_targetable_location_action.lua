local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local TrainMoveToTargetableLocation = class()

TrainMoveToTargetableLocation.name = 'train move to targetable location'
TrainMoveToTargetableLocation.does = 'stonehearth_ace:train_move_to_targetable_location'
TrainMoveToTargetableLocation.args = {
	target = Entity
}
TrainMoveToTargetableLocation.priority = 0.5

local log = radiant.log.create_logger('training_action')
local combat = stonehearth.combat

function TrainMoveToTargetableLocation:start_thinking(ai, entity, args)
	ai:set_think_output({location = find_training_location(entity, args.target)})
end

function TrainMoveToTargetableLocation:start(ai, entity, args)
	-- add listener for training disabled
	self._training_enabled_listener = radiant.events.listen(entity, 'stonehearth_ace:training_enabled_changed', 
				function(enabled) 
					self:_on_training_enabled_changed(ai, enabled)
				end)
end

function TrainMoveToTargetableLocation:stop(ai, entity, args)
	if self._training_enabled_listener then
		self._training_enabled_listener:destroy()
		self._training_enabled_listener = nil
	end
end

function find_training_location(entity, target)
	local weapon = combat:get_main_weapon(entity)
	local weapon_data = radiant.entities.get_entity_data(weapon, 'stonehearth:combat:weapon_data')
	local min_range, max_range
	if weapon_data.range then
		-- it's a ranged combat class so get the range including any bonus range
		min_range = 5
		max_range = combat:get_weapon_range(entity, weapon)
	else
		-- otherwise it's melee so get the reach
		min_range, max_range = combat:get_melee_range(entity, weapon_data, target)
		-- it's melee so max range doesn't really matter
		max_range = min_range
	end

	if not min_range or not max_range then
		return radiant.entities.get_grid_in_front(target)
		--ai:abort('entity has no weapon range')
	end

	-- determine the direction the target is facing
	-- get a location at max_range in front of the target
	-- test and go closer until it's a valid location (i.e., it has line of sight; don't worry about reachability for now)

	local mob = target:get_component('mob')
	local facing = radiant.math.round(mob:get_facing() / 90) * 90
	local location = mob:get_world_grid_location()
	local best_location = nil
   local rng = _radiant.math.get_default_rng()
   local min_dist = min_range * min_range
   local max_dist = max_range * max_range

   -- give it 10 tries; if it hasn't found a spot, move on
   for i = 1, 10 do
      local distance = math.sqrt(rng:get_real(min_dist, max_dist))
		local varied_facing = facing + rng:get_real(-18, 18)
		local temp_location = get_location_in_front(location, varied_facing, distance)
		local line_of_sight = _physics:has_line_of_sight(target, Point3(temp_location.x, temp_location.y + 2, temp_location.z))
		if line_of_sight then
			best_location = temp_location
			break
		end
	end

	if not best_location then
		best_location = get_location_in_front(location, facing, min_range)
	end
	return best_location
end

function get_location_in_front(location, facing, distance)
	local offset = radiant.math.rotate_about_y_axis(-Point3(0, 0, distance), facing)
	return location + offset
end

local ai = stonehearth.ai
return ai:create_compound_action(TrainMoveToTargetableLocation)
         :execute('stonehearth:go_toward_location', {
            reason = 'move to targetable location',
            destination = ai.PREV.location
         })