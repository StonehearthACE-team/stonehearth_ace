--[[
   not currently getting monkey-patched in
   the goal is to allow for population-specific jobs for citizens of different populations in the same kingdom
   e.g., an orc footman may have different skills/traits than an ascendancy footman
   also then allows for promotion to kingdom-specific classes (e.g., goblin shaman in a non-goblin kingdom)
]]

local PlayerJobsController = require 'stonehearth.services.server.job.player_jobs_controller'
local AcePlayerJobsController = class()

-- For a given player, keep a table of job_info_controllers for that player

-- empty all state
AcePlayerJobsController._ace_old_clear = PlayerJobsController.clear
function AcePlayerJobsController:clear()
   self:_ace_old_clear()

   self._population_job_indexes = {}
end

function AcePlayerJobsController:_ensure_job_id(id)
   self:_ensure_job_index()

   if self._job_index and self._job_index.jobs and self._job_index.jobs[id] then
      local info = self._job_index.jobs[id]
      self._sv.jobs[id] = radiant.create_controller('stonehearth:job_info_controller', info, self._sv.player_id)
      self.__saved_variables:mark_changed()
   end
end

--If we have kingdom data for this job, use that, instead of the default
function AcePlayerJobsController:_ensure_job_index(population_override)
   if not self._job_index then
      local pop = stonehearth.population:get_population(self._sv.player_id)
      local job_index_location = 'stonehearth:jobs:index'
      if pop then
         job_index_location = pop:get_job_index()
      end
      self._job_index = radiant.resources.load_json(job_index_location)
   end
end

--If we have kingdom data for this job, use that, instead of the default
function AcePlayerJobsController:get_job_description(job_uri, population_override)
   local jobs = self:_ensure_job_index(population_override)
   if self._job_index and self._job_index.jobs and self._job_index.jobs[job_uri] then
      return self._job_index.jobs[job_uri].description
   else
      return job_uri
   end
end

return AcePlayerJobsController
