local BlueprintsToBuildingPiecesJob = require 'stonehearth.components.building2.plan.jobs.blueprints_to_building_pieces_job'
local AceBlueprintsToBuildingPiecesJob = class()

AceBlueprintsToBuildingPiecesJob._ace_old_create = BlueprintsToBuildingPiecesJob.create
function AceBlueprintsToBuildingPiecesJob:create(job_data)
   self:_ace_old_create(job_data)
   self._sv._insert_craft_requests = job_data.insert_craft_requests
end

AceBlueprintsToBuildingPiecesJob._ace_old_get_results = BlueprintsToBuildingPiecesJob.get_results
function AceBlueprintsToBuildingPiecesJob:get_results()
   local result = self:_ace_old_get_results()
   result.insert_craft_requests = self._sv._insert_craft_requests
   return result
end

return AceBlueprintsToBuildingPiecesJob
