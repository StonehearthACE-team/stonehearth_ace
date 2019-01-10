local Entity = _radiant.om.Entity
local validator = radiant.validator

local EvolveCallHandler = class()

function EvolveCallHandler:use_evolve_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local evolve_comp = entity:get_component('stonehearth:evolve')
   if evolve_comp then
      evolve_comp:request_evolve(session.player_id)
   else
      return false
   end
end

return EvolveCallHandler