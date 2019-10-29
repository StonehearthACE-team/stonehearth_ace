local BaseJob = require 'stonehearth.jobs.base_job'
local AceCombatJob = class()

function AceCombatJob:initialize()
   BaseJob.__user_initialize(self)
   self._sv._accumulated_town_protection_time = 0
end

return AceCombatJob
