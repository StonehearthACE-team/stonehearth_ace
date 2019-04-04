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

function _should_abort(source, training_enabled)
   return not training_enabled
end

local ai = stonehearth.ai
return ai:create_compound_action(Train)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:training_enabled_changed',
            filter_fn = _should_abort
         })
         :execute('stonehearth:drop_backpack_contents_on_ground', {})
		   :execute('stonehearth:set_posture', { posture = 'stonehearth:combat' })
         :execute('stonehearth_ace:find_training_dummy')
         :execute('stonehearth_ace:train_attack', { target = ai.BACK(1).dummy })
