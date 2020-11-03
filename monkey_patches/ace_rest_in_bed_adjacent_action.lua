local RestInBedAdjacent = require 'stonehearth.ai.actions.health.rest_in_bed_adjacent_action'
local AceRestInBedAdjacent = radiant.class()

AceRestInBedAdjacent._ace_old_stop = RestInBedAdjacent.stop
function AceRestInBedAdjacent:stop(ai, entity, args)
   -- don't need to get out of bed if we're incapacitated
   local incapacitation = entity:get_component('stonehearth:incapacitation')
   if incapacitation and incapacitation:is_incapacitated() then
      return
   end
   
   self:_ace_old_stop(ai, entity, args)
end

return AceRestInBedAdjacent
