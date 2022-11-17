local CrafterJobsNode = require 'stonehearth.components.building2.plan.nodes.crafter_jobs_node'

local log = radiant.log.create_logger('build.plan_job')

local ComputePlanJob = require 'stonehearth.components.building2.plan.jobs.plan_job'
local AceComputePlanJob = class()

AceComputePlanJob._ace_old_create = ComputePlanJob.create
function AceComputePlanJob:create(job_data)
   self:_ace_old_create(job_data)
   self._sv._insert_craft_requests = job_data.insert_craft_requests
end

function AceComputePlanJob:compute_crafter_jobs()
   log:info('compute_crafter_jobs')

   local resources, items = self._sv._building:get('stonehearth:build2:building'):get_costs()

   self._sv._plan:push_node_front(CrafterJobsNode(self._sv._building, items, resources, self._sv._insert_craft_requests))

   log:info('done compute_crafter_jobs')
   self:incstage()
end

return AceComputePlanJob
