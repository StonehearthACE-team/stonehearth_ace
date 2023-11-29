local BlueprintJob = require 'stonehearth.components.building2.plan.jobs.blueprint_job'
local AceBlueprintJob = class()

AceBlueprintJob._ace_old_create = BlueprintJob.create
function AceBlueprintJob:create(job_data)
   self:_ace_old_create(job_data)
   self._sv._insert_craft_requests = job_data.insert_craft_requests
   self._sv._terrain_cutout = job_data.terrain_cutout
end

AceBlueprintJob._ace_old_get_results = BlueprintJob.get_results
function AceBlueprintJob:get_results()
   local result = self:_ace_old_get_results()
   result.insert_craft_requests = self._sv._insert_craft_requests
   result.terrain_cutout = self._sv._terrain_cutout
   return result
end

return AceBlueprintJob
