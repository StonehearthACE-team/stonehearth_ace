local CraftingJob = require 'stonehearth.jobs.crafting_job'
local AceEngineerClass = class()

function AceEngineerClass:initialize()
   CraftingJob.__user_initialize(self)
   self._sv.max_num_siege_weapons = {}
end

return AceEngineerClass
