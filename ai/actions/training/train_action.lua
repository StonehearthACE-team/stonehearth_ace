local Point3 = _radiant.csg.Point3
local Train = class()

Train.name = 'train'
Train.status_text_key = 'stonehearth_ace:ai.actions.status_text.train'
Train.does = 'stonehearth_ace:train'
Train.args = {}
Train.priority = 0.6

local log = radiant.log.create_logger('training_action')
local combat = stonehearth.combat

-- the entity first checks to see if they're below level 6 and have training enabled
-- then they seek out a training dummy and acquire a lease on it
-- then they run to a position where they're in range of attacking it
-- then they play their attack animation to "damage" the dummy and gain experience and release their lease
-- this is the end of the action; they may then decide to do it again and might choose a slightly different position

function Train:start_thinking(ai, entity, args)
   -- check if we're eligible (below level 6, training enabled)
	local job = entity:get_component('stonehearth:job')
	if not job:is_trainable() then
		ai:reject('entity cannot train')
		return
	end
	
	if not job:get_training_enabled() then
		ai:reject('training is disabled or unavailable for this entity')
		return
	end

	ai:set_think_output({entity = entity})
end

function Train:start(ai, entity, args)
	-- add listener for training disabled
	self._training_enabled_listener = radiant.events.listen(entity, 'stonehearth_ace:training_enabled_changed', 
				function(enabled) 
					self:_on_training_enabled_changed(ai, enabled)
				end)
end

function Train:stop(ai, entity, args)
	if self._training_enabled_listener then
		self._training_enabled_listener:destroy()
		self._training_enabled_listener = nil
	end
end

function Train:_on_training_enabled_changed(ai, enabled)
	if not enabled then
		ai:abort('training was disabled for this entity')
	end
end

function find_training_dummy(entity)
   local player_id = entity:get_player_id()
   local job_uri = entity:get_component('stonehearth:job'):get_job_uri()
   
   return stonehearth.ai:filter_from_key('stonehearth_ace:training_dummy:'..job_uri, player_id,
		function(target)
			if stonehearth.player:are_player_ids_friendly(player_id, target) then
            local training_dummy = target:get_component('stonehearth_ace:training_dummy')
            return training_dummy and training_dummy:can_train_entity(job_uri) or false
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
   local rng = _radiant.math.get_default_rng()
   local min_dist = min_range * min_range
   local max_dist = max_range * max_range

   -- give it 10 tries; if it hasn't found a spot, move on
   for i = 1, 10 do
      local distance = math.sqrt(rng:get_real(min_dist, max_dist))
		local varied_facing = facing + rng:get_real(-18, 18)
		local temp_location = get_location_in_front(location, varied_facing, distance)
		--if not next(radiant.terrain.get_entities_at_point(temp_location)) then
			local line_of_sight = _physics:has_line_of_sight(target, Point3(temp_location.x, temp_location.y + 2, temp_location.z))
			if line_of_sight then
				best_location = temp_location
				break
			end
		--end
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
return ai:create_compound_action(Train)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:drop_backpack_contents_on_ground', {})
		 :execute('stonehearth:set_posture', { posture = 'stonehearth:combat' })
         :execute('stonehearth:find_best_reachable_entity_by_type', 
					{ filter_fn = ai.CALL(find_training_dummy, ai.ENTITY)})
         --:execute('stonehearth:reserve_entity', { entity = ai.PREV.item })
         :execute('stonehearth:find_path_to_location', { location = ai.CALL(find_training_location, ai, ai.ENTITY, ai.BACK(1).item) })
		 :execute('stonehearth:follow_path', { path = ai.PREV.path })
		 --:execute('stonehearth:combat:move_to_targetable_location', { target = ai.BACK(4).item })
	-- now can we just tell our entity to attack the target, even though it's not an enemy? yes!
	-- queue up four attacks so the unit doesn't think about running away and repositioning after every attack
		 :execute('stonehearth_ace:train_attack', { target = ai.BACK(3).item })
		 :execute('stonehearth_ace:train_attack', { target = ai.BACK(4).item })
		 :execute('stonehearth_ace:train_attack', { target = ai.BACK(5).item })
		 :execute('stonehearth_ace:train_attack', { target = ai.BACK(6).item })