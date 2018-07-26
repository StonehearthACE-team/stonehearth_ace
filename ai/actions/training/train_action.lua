local Point3 = _radiant.csg.Point3
local Train = class()

Train.name = 'train'
Train.status_text_key = 'stonehearth_ace:ai.actions.status_text.train'
Train.does = 'stonehearth_ace:train'
Train.args = {}
Train.priority = 1

local log = radiant.log.create_logger('training_action')
local combat = stonehearth.combat

-- the entity first checks to see if they're below level 6 and have training enabled
-- then they seek out a training dummy and acquire a lease on it
-- then they run to a position where they're in range of attacking it
-- then they play their attack animation to "damage" the dummy and gain experience and release their lease
-- this is the end of the action; they may then decide to do it again and might choose a slightly different position

function Train:start_thinking(ai, entity, args)
	-- check if we're eligible (below level 6, training enabled)
	local job_component = entity:get_component('stonehearth:job')
	if job_component:is_max_level() then
		ai:reject('entity is max level, cannot train')
		return
	end
	if radiant.entities.get_attribute(entity, 'stonehearth_ace:training_enabled', 1) ~= 1 then
		ai:reject('training is disabled for this entity')
		return
	end
	ai:set_think_output()
end

function Train:stop_thinking(ai, entity, args)
	
end

function find_training_dummy(entity)
	return stonehearth.ai:filter_from_key('stonehearth_ace:training_dummy', entity:get_player_id(),
		function(target)
			if stonehearth.player:are_entities_friendly(entity, target) then
				return target:get_component('stonehearth_ace:training_dummy') ~= nil
			end
			return false
		end)
end

function find_training_location(ai, entity, target)
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

	for distance = max_range, min_range, -0.5 do
		local temp_location = get_location_in_front(location, facing, distance)
		local line_of_sight = _physics:has_line_of_sight(target, Point3(temp_location.x, temp_location.y + 2, temp_location.z))
		if line_of_sight then
			best_location = temp_location
			break
		end
	end

	if best_location then
		return best_location
	else
		ai:abort('cannot find suitable training location for this training dummy')
	end
end

function get_location_in_front(location, facing, distance)
	local offset = radiant.math.rotate_about_y_axis(-Point3(0, 0, distance), facing)
	return location + offset
end

local ai = stonehearth.ai
return ai:create_compound_action(Train)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:drop_backpack_contents_on_ground', {})
		 :execute('stonehearth:set_posture', { posture = 'stonehearth:combat' })
         :execute('stonehearth:find_best_reachable_entity_by_type', 
					{ filter_fn = ai.CALL(find_training_dummy, ai.ENTITY)})
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.item })
         :execute('stonehearth:find_path_to_location', { location = ai.CALL(find_training_location, ai, ai.ENTITY, ai.BACK(2).item) })
		 :execute('stonehearth:follow_path', { path = ai.PREV.path })
	-- now can we just tell our entity to attack the target, even though it's not an enemy? yes!
		 :execute('stonehearth:combat:attack_melee_adjacent', { target = ai.BACK(4).item })	-- need to use ranged attack call if entity is ranged
		 -- but we want them to keep attacking (and gaining experience) until it's "dead" or they find something better to do
		 -- JobComponent:add_exp(value, add_curiosity_addition)