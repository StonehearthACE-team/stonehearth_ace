local PeriodicInteraction = radiant.class()

PeriodicInteraction.name = 'periodic interaction (current user)'
PeriodicInteraction.does = 'stonehearth_ace:periodic_interaction'
PeriodicInteraction.args = {}
PeriodicInteraction.priority = 1.0

local function _interact_filter_fn(user_id, item)
   local periodic_interaction = item:get_component('stonehearth_ace:periodic_interaction')
   if not periodic_interaction or not periodic_interaction:is_usable() then
      return false
   end

   local user = periodic_interaction:get_current_user()
   return user and user:get_id() == user_id
end

-- prefer higher level ones we're capable of interacting with
local function _interact_rating_fn(job_level, item)
   local rating = 0
   local pi_comp = item:get_component('stonehearth_ace:periodic_interaction')
   if pi_comp then
      local level_req = pi_comp:get_current_mode_job_level_requirement()
      if level_req then
         -- job_level >= the requirement if it's filtered as a valid entity
         rating = pi_comp:get_current_mode_job_level_requirement() / job_level
      end
   end
   return rating
end

function PeriodicInteraction:start_thinking(ai, entity, args)
   local player_id = radiant.entities.get_work_player_id(entity)
   local job_component = entity:get_component('stonehearth:job')
   local job_level = job_component:get_current_job_level()
   local user_id = entity:get_id()

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:periodic_interaction (current user)', user_id, function(item)
         return _interact_filter_fn(user_id, item)
      end)
      
   local rating_fn = function(item)
         return _interact_rating_fn(job_level, item)
      end

   -- only abort if we haven't found something to interact with yet
   -- (we want to abort on level up so we can re-filter entities that we're now of an appropriate level to interact with)
   local should_abort = function()
         return not self._started
      end

   if not ai.CURRENT.carrying then
      ai:set_think_output({
         filter_fn = filter_fn,
         rating_fn = rating_fn,
         owner_player_id = player_id,
         should_abort = should_abort
      })
   end
end

function PeriodicInteraction:start(ai, entity, args)
   self._started = true
end

function PeriodicInteraction:stop(ai, entity, args)
   self._started = nil
end

local ai = stonehearth.ai
return ai:create_compound_action(PeriodicInteraction)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:level_up',
            filter_fn = ai.BACK(2).should_abort
         })
         -- :execute('stonehearth:abort_on_event_triggered', {
         --    source = ai.ENTITY,
         --    event_name = 'stonehearth:equipment_changed',
         --    filter_fn = ai.BACK(2).should_abort
         -- })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(3).filter_fn,
            rating_fn = ai.BACK(3).rating_fn,
            description = 'finding periodic interaction entities',
            owner_player_id = ai.BACK(3).owner_player_id
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(4).filter_fn,
            item = ai.BACK(1).item
         })
         :execute('stonehearth_ace:periodic_interaction_entity', {
            item = ai.BACK(2).item
         })
