local RestWhenInjured = radiant.class()
RestWhenInjured.name = 'rest when injured'
RestWhenInjured.does = 'stonehearth:rest_when_injured'
RestWhenInjured.args = {}
RestWhenInjured.priority = {0, 1}

function RestWhenInjured:start_thinking(ai, entity, args)
   -- check if it's a combat job; if so, use the combat rest when injured percentage
   local injured_percentage
   local job = entity:get_component('stonehearth:job')
   local job_info = job and job:get_job_info()
   if job_info and job_info:is_combat_job() then
      injured_percentage = stonehearth.constants.health.COMBAT_REST_WHEN_INJURED_PERCENTAGE
   else
      injured_percentage = stonehearth.constants.health.REST_WHEN_INJURED_PERCENTAGE
   end

   self._injured_percentage = injured_percentage
   ai:set_think_output({
      injured_percentage = injured_percentage
   })
end

function RestWhenInjured:compose_utility(entity, self_utility, child_utilities, current_activity)
   return 1.0 - child_utilities:get(0) / self._injured_percentage
end

local ai = stonehearth.ai
return ai:create_compound_action(RestWhenInjured)
            :execute('stonehearth:abort_on_event_triggered', {
               source = ai.ENTITY,
               event_name = 'stonehearth:job_changed',
            })
            :execute('stonehearth:wait_for_expendable_resource_below_percentage', {
                  resource_name = 'health',
                  percentage = ai.BACK(2).injured_percentage
               })
            :execute('stonehearth:rest_from_injuries')
