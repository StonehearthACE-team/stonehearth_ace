local WaitForRequiredJobs = class()

local log = radiant.log.create_logger('wait_for_required_jobs')

function WaitForRequiredJobs:start(ctx, info)
   local player_job_controller = stonehearth.job:get_player_job_controller(ctx.player_id)
   if not player_job_controller then
      log:debug('no player job controller for player id "%s"', ctx.player_id)
      return false
   end

   for job, level in pairs(info.jobs) do
      local job_info = stonehearth.job:get_job_info(ctx.player_id, job)
      if job_info then
         local job_level = job_info:get_highest_level()
         if job_level >= level then
            return true
         end
      end
   end
end

return WaitForRequiredJobs
