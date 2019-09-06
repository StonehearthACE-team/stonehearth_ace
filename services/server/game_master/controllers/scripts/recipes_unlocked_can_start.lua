local RecipesUnlockedCanStart = class()

function RecipesUnlockedCanStart:start(ctx, info)
   local player_job_controller = stonehearth.job:get_player_job_controller(ctx.player_id)
   if not player_job_controller then
      return false
   end

   for job, data in pairs(info.jobs) do
      local job_info = player_job_controller:get_job(job)
      if job_info then
         local has_any_recipe = false
         local unlocked = job_info:get_manually_unlocked()
         for _, recipe in pairs(data.recipes) do
            local has_recipe = unlocked[recipe]
            if data.type == 'any' and has_recipe then
               has_any_recipe = true
               break
            elseif data.type == 'all' and not has_recipe then
               return false
            end
         end

         if not has_any_recipe then
            return false
         end
      else
         return false
      end
   end

   return true
end

return RecipesUnlockedCanStart
