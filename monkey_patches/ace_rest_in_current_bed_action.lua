local RestInCurrentBed = require 'stonehearth.ai.actions.health.rest_in_current_bed_action'
local AceRestInCurrentBed = radiant.class()

AceRestInCurrentBed._ace_old_stop = RestInCurrentBed.stop
function AceRestInCurrentBed:stop(ai, entity, args)
   -- don't need to get out of bed if we're incapacitated
   local incapacitation = entity:get_component('stonehearth:incapacitation')
   if incapacitation and incapacitation:is_incapacitated() then
      return
   end
   
   self:_ace_old_stop(ai, entity, args)
end

return AceRestInCurrentBed
