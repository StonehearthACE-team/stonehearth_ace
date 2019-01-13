local PerformEvolveItem = radiant.class()
local log = radiant.log.create_logger('perform_evolve')

PerformEvolveItem.name = 'perform evolve'
PerformEvolveItem.does = 'stonehearth_ace:perform_evolve'
PerformEvolveItem.args = {
   category = 'string',  -- The category for resource evolving
}
PerformEvolveItem.priority = {0.0, 1.0}

local function _perform_evolve_filter_fn(player_id, job_uri, category, item)
   if not item or not item:is_valid() then
      return false
   end

   local evolve = item:get_component('stonehearth:evolve')
   if not evolve then
      return false
   end

   --log:debug('checking %s in filter for %s _ %s _ %s', item, player_id, job_uri, category)

   -- make sure the entity has an appropriate job
   local data = radiant.entities.get_entity_data(item, 'stonehearth:evolve_data')
   if not data or (data.evolve_worker_required_job and not data.evolve_worker_required_job[job_uri]) then
      return false
   end

   local task_tracker_component = item:get_component('stonehearth:task_tracker')
   if not task_tracker_component then
      return false
   end

   return task_tracker_component:is_task_requested(player_id, category, PerformEvolveItem.does)
end

function PerformEvolveItem:start_thinking(ai, entity, args)
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local category = args.category
   local job_comp = entity:get_component('stonehearth:job')
   local job_uri = job_comp and job_comp:get_job_uri() or ''

   --log:debug('making filter function for %s with job %s', entity, job_uri)
   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:perform_evolve', work_player_id .. '_' .. job_uri .. '_' .. category, function(item)
         return _perform_evolve_filter_fn(work_player_id, job_uri, category, item)
      end)

   ai:set_think_output({
      filter_fn = filter_fn,
      owner_player_id = work_player_id,
   })
end

function PerformEvolveItem:compose_utility(entity, self_utility, child_utilities, current_activity)
   return self_utility * 0.9 + child_utilities:get('stonehearth:find_best_reachable_entity_by_type') * 0.1
end

local ai = stonehearth.ai
return ai:create_compound_action(PerformEvolveItem)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:haul:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:job_changed',
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(3).filter_fn,
            description = 'finding evolvable items',
            owner_player_id = ai.BACK(3).owner_player_id,
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(4).filter_fn,
            item = ai.BACK(1).item,
         })
         :execute('stonehearth:reserve_entity', {
            owner_player_id = ai.BACK(5).owner_player_id,
            item = ai.BACK(2).item,
         })
         :execute('stonehearth_ace:perform_evolve_on_entity', {
            owner_player_id = ai.BACK(6).owner_player_id,
            item = ai.BACK(3).item,
         })
