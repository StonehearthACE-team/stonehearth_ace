--[[
   Returned a carried citizen to an unused and unowned bed
]]
local shared_filters = require 'stonehearth.ai.filters.shared_filters'
local Entity = _radiant.om.Entity

local ReturnCarriedCitizenToPriorityCareBed = radiant.class()
ReturnCarriedCitizenToPriorityCareBed.name = 'rescue citizen'
ReturnCarriedCitizenToPriorityCareBed.does = 'stonehearth:return_carried_citizen_to_town'
ReturnCarriedCitizenToPriorityCareBed.args = {
   citizen = Entity, -- the entity to rescue
}
ReturnCarriedCitizenToPriorityCareBed.priority = 1.0

local ai = stonehearth.ai
return ai:create_compound_action(ReturnCarriedCitizenToPriorityCareBed)
         :execute('stonehearth:goto_entity_type', {
            filter_fn = ai.CALL(shared_filters.make_is_priority_care_available_bed_filter, ai.ARGS.citizen),
            description = 'return carried citizen to priority care bed'
         })
         :execute('stonehearth:reserve_entity', { entity = ai.PREV.destination_entity })
         :execute('stonehearth:drop_carried_citizen', { citizen = ai.ARGS.citizen, bed = ai.PREV.entity })
