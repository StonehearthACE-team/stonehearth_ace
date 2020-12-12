local HuntAnimalAction = radiant.class()

HuntAnimalAction.name = 'hunt animal'
HuntAnimalAction.does = 'stonehearth_ace:hunt_animal'
HuntAnimalAction.args = {
   category = 'string',  -- The category for hunting
}
HuntAnimalAction.priority = {0.0, 1.0}

local function _hunt_filter_fn(player_id, category, entity)
   if not entity or not entity:is_valid() then
      return false
   end

   if radiant.entities.get_player_id(entity) ~= 'animals' then
      return false
   end

   local task_tracker_component = entity:get_component('stonehearth:task_tracker')
   if not task_tracker_component then
      return false
   end

   return task_tracker_component:is_task_requested(player_id, category, HuntAnimalAction.does)
end

function HuntAnimalAction:start_thinking(ai, entity, args)
   local work_player_id = radiant.entities.get_work_player_id(entity)
   local category = args.category

   local filter_fn = stonehearth.ai:filter_from_key('stonehearth_ace:hunt_animal', work_player_id .. ':' .. category, function(item)
         return _hunt_filter_fn(work_player_id, category, item)
      end)

   local set_think_output = function()
      ai:set_think_output({
         hunt_filter_fn = filter_fn,
         owner_player_id = work_player_id,
      })
   end

   -- if the entity has hunting disabled, don't set the output; wait for hunting to be enabled to do so
   local properties_comp = entity:get_component('stonehearth:properties')
   local avoid_hunting = properties_comp and properties_comp:has_property('avoid_hunting')
   if avoid_hunting then
      self._allow_hunting_listener = radiant.events.listen(entity, 'stonehearth_ace:avoid_hunting_changed', function()
            if properties_comp:has_property('avoid_hunting') then
               set_think_output()
            end
         end)
   else
      set_think_output()
   end
end

function HuntAnimalAction:stop_thinking(ai, entity, args)
   if self._allow_hunting_listener then
      self._allow_hunting_listener:destroy()
      self._allow_hunting_listener = nil
   end
end

function HuntAnimalAction:compose_utility(entity, self_utility, child_utilities, current_activity)
   return self_utility * 0.9 + child_utilities:get('stonehearth_ace:loop_hunt_animal') * 0.1
end

local ai = stonehearth.ai
return ai:create_compound_action(HuntAnimalAction)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:avoid_hunting_changed',
         })
         :execute('stonehearth:find_best_reachable_entity_by_type', {
            filter_fn = ai.BACK(3).hunt_filter_fn,
            description = 'finding huntable animal',
            owner_player_id = ai.BACK(3).owner_player_id,
         })
         :execute('stonehearth:abort_on_reconsider_rejected', {
            filter_fn = ai.BACK(4).hunt_filter_fn,
            item = ai.BACK(1).item,
         })
         :execute('stonehearth:set_posture', { posture = 'stonehearth:combat' })
         :execute('stonehearth_ace:loop_hunt_animal', {
            target = ai.BACK(3).item,
         })
