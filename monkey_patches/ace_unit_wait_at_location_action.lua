local UnitWaitAtLocation = require 'stonehearth.ai.actions.unit_control.unit_wait_at_location_action'
local AceUnitWaitAtLocation = class()

local DEFENSE_POSTURE_BUFF = 'stonehearth_ace:buffs:guarding'

-- apply the buff in run rather than start so they're already at the location
AceUnitWaitAtLocation._ace_old_run = UnitWaitAtLocation.run
function AceUnitWaitAtLocation:run(ai, entity, args)
   radiant.entities.add_buff(entity, DEFENSE_POSTURE_BUFF)

   self:_ace_old_run(ai, entity, args)
end

AceUnitWaitAtLocation._ace_old_stop = UnitWaitAtLocation.stop
function AceUnitWaitAtLocation:stop(ai, entity, args)
   radiant.entities.remove_buff(entity, DEFENSE_POSTURE_BUFF)
   
   self:_ace_old_stop(ai, entity, args)
end

return AceUnitWaitAtLocation
