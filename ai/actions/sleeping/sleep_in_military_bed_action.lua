
   

local shared_filters = require 'stonehearth.ai.filters.shared_filters'
local SleepInMilitaryBed = radiant.class()

SleepInMilitaryBed.name = 'sleep in military bed'
SleepInMilitaryBed.does = 'stonehearth:sleep'
SleepInMilitaryBed.args = {}
SleepInMilitaryBed.priority = 0.5

function SleepInMilitaryBed:start_thinking(ai, entity, args)
   local job_component = entity:get_component('stonehearth:job')
   if job_component then
      if job_component:has_role('combat') then
         ai:set_think_output({})
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(SleepInMilitaryBed)
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:goto_entity_type', {
            filter_fn = ai.CALL(shared_filters.make_is_military_available_bed_filter, ai.ENTITY),
            description = 'sleep in new bed'
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.destination_entity })
         :execute('stonehearth:set_posture', { posture = 'stonehearth:sleeping' })
         :execute('stonehearth:sleep_in_bed_adjacent', { bed = ai.BACK(2).entity })
