local CraftingJob = require 'stonehearth.jobs.crafting_job'

local BrewerClass = class()
radiant.mixin(BrewerClass, CraftingJob)

return BrewerClass
