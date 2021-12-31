local PeriodicInteraction = radiant.class()

PeriodicInteraction.name = 'tend herbalist planter'
PeriodicInteraction.does = 'stonehearth_ace:periodic_interaction'
PeriodicInteraction.args = {}
PeriodicInteraction.priority = 0

local function _interact_filter_fn(player_id, job_uri, job_level, item)
   if not item or not item:is_valid() then
      return false
   end

   if radiant.entities.get_player_id(item) ~= player_id then
      return false
   end

   local periodic_interaction = item:get_component('stonehearth_ace:periodic_interaction')
   if periodic_interaction then
      -- TODO: need to add "owner"/current_user filtering here as well
      local job_req = periodic_interaction:get_current_mode_job_requirement()
      local level_req = periodic_interaction:get_current_mode_job_level_requirement()
      return not job_req or (job_uri == job_req and (not level_req or job_level >= level_req))
   end
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
   local job_uri = job_component:get_job_uri()
   local job_level = job_component:get_current_job_level()
   local key = player_id .. '|' .. job_uri .. '|' .. job_level

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:periodic_interaction', key, function(item)
         return _interact_filter_fn(player_id, job_uri, job_level, item)
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
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:equipment_changed',
            filter_fn = ai.BACK(2).should_abort
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(4).filter_fn,
            rating_fn = ai.BACK(4).rating_fn,
            description = 'finding tendable herbalist planters',
            owner_player_id = ai.BACK(4).owner_player_id
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(5).filter_fn,
            item = ai.BACK(1).item
         })
         :execute('stonehearth:reserve_entity', {
            entity = ai.BACK(2).item
         })
         :execute('stonehearth:find_path_to_reachable_entity', {
            destination = ai.BACK(3).item
         })
         :execute('stonehearth:follow_path', {
            path = ai.PREV.path
         })
         :execute('stonehearth_ace:periodic_interaction_adjacent', {
            item = ai.BACK(5).item
         })
