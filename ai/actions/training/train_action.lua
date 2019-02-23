local Point3 = _radiant.csg.Point3
local Train = class()

Train.name = 'train'
Train.status_text_key = 'stonehearth_ace:ai.actions.status_text.train'
Train.does = 'stonehearth_ace:train'
Train.args = {}
Train.priority = 0.5

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
			if stonehearth.player:are_player_ids_friendly(player_id, target:get_player_id()) then
				local training_dummy = target:get_component('stonehearth_ace:training_dummy')
				return training_dummy and training_dummy:can_train_entity(job_uri) or false
			end
			return false
		end)
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
		   :execute('stonehearth_ace:train_attack', { target = ai.BACK(1).item })