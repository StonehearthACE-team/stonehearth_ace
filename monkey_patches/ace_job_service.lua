local JobService = require 'stonehearth.services.server.job.job_service'
local AceJobService = class()

AceJobService._ace_old__load_all_job_data = JobService._load_all_job_data
function AceJobService:_load_all_job_data()
   self:_ace_old__load_all_job_data()
   self:_load_kingdom_job_data()
end

function AceJobService:_load_kingdom_job_data()
   -- just use the playable kingdoms job index if there are other (e.g., monster/npc) kingdoms adding jobs,
   -- we don't really care about their perks probably?
   -- if we decide to care, just do the same for 'stonehearth:data:npc_index'
   local kingdoms = radiant.resources.load_json('stonehearth:playable_kingdom_index').kingdoms
   for _, kingdom_uri in pairs(kingdoms) do
      local kingdom = radiant.resources.load_json(kingdom_uri)
      local jobs = radiant.resources.load_json(kingdom.job_index).jobs
      for job_alias, job_info in pairs(jobs) do
         local alias = job_info.description
         if not self._all_job_data.jobs[alias] then
            local job_description = radiant.deep_copy(radiant.resources.load_json(alias))
            job_description.is_worker = job_description.alias == 'stonehearth:jobs:worker'
            job_description.generic_alias = job_description.alias
            job_description.alias = alias
            self._all_job_data.jobs[alias] = {
               description = job_description
            }
         end
      end
   end
end

function AceJobService:get_job_info(player_id, job_id, population_override)
   local player = self._sv.players[player_id]
   if not player then
      return
   end
   return player:get_job(job_id, population_override)
end

function AceJobService:unlock_all_recipes_and_crops(player_id)
   local player = self._sv.players[player_id]
   if not player then
      return
   end
   return player:unlock_all_recipes_and_crops()
end

return AceJobService