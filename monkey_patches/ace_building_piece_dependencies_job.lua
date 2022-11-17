local BuildingPieceDependenciesJob = require 'stonehearth.components.building2.plan.jobs.building_piece_dependencies_job'
local AceBuildingPieceDependenciesJob = class()

AceBuildingPieceDependenciesJob._ace_old_create = BuildingPieceDependenciesJob.create
function AceBuildingPieceDependenciesJob:create(job_data)
   self:_ace_old_create(job_data)
   self._sv._insert_craft_requests = job_data.insert_craft_requests
end

AceBuildingPieceDependenciesJob._ace_old_get_results = BuildingPieceDependenciesJob.get_results
function AceBuildingPieceDependenciesJob:get_results()
   local result = self:_ace_old_get_results()
   result.insert_craft_requests = self._sv._insert_craft_requests
   return result
end

return AceBuildingPieceDependenciesJob
