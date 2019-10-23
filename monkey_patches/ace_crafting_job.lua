local BaseJob = require 'stonehearth.jobs.base_job'
local AceCraftingJob = class()

function AceCraftingJob:initialize()
   BaseJob.__user_initialize(self)
end

return AceCraftingJob
