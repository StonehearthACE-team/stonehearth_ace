--[[
   Returns a carried citizen to the bed that the carried citizen owns
]]

local Entity = _radiant.om.Entity

local ReturnCarriedCitizenToOwnBed = radiant.class()
ReturnCarriedCitizenToOwnBed.name = 'return citizen to owned bed'
ReturnCarriedCitizenToOwnBed.does = 'stonehearth:return_carried_citizen_to_town'
ReturnCarriedCitizenToOwnBed.args = {
   citizen = Entity, -- the entity to rescue
}
ReturnCarriedCitizenToOwnBed.priority = 0.7

function ReturnCarriedCitizenToOwnBed:start_thinking(ai, entity, args)
   local carried_citizen = args.citizen
   local object_owner_component = carried_citizen:get_component('stonehearth:object_owner')
   local bed = object_owner_component and object_owner_component:get_owned_object('bed')
   if bed and bed:is_valid() then
      ai:set_think_output({ owned_bed = bed })
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(ReturnCarriedCitizenToOwnBed)
      :execute('stonehearth:reserve_entity', { entity = ai.PREV.owned_bed })
      :execute('stonehearth:goto_entity', { entity = ai.BACK(2).owned_bed })
      :execute('stonehearth:drop_carried_citizen', { citizen = ai.ARGS.citizen, bed = ai.BACK(3).owned_bed })
