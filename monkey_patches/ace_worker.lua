local BaseJob = require 'stonehearth.jobs.base_job'
local AceWorkerClass = class()

function AceWorkerClass:initialize()
   BaseJob.__user_initialize(self)
   self._sv.no_levels = true
   self._sv.is_max_level = true
end

return AceWorkerClass
