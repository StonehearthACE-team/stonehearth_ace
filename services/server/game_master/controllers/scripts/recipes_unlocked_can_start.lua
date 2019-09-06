local RecipesUnlockedCanStart = class()

local log = radiant.log.create_logger('recipes_unlocked_can_start')

function RecipesUnlockedCanStart:start(ctx, info)
   local player_job_controller = stonehearth.job:get_player_job_controller(ctx.player_id)
   if not player_job_controller then
      log:debug('no player job controller for player id "%s"', ctx.player_id)
      return false
   end

   for job, data in pairs(info.jobs) do
      --log:debug('checking job %s for player %s', job, ctx.player_id)
      local job_info = player_job_controller:get_job(job)
      if job_info then
         local has_any_recipe = false
         local unlocked = job_info:get_manually_unlocked()
         --log:debug('has the following %s recipes unlocked: %s', radiant.size(unlocked), radiant.util.table_tostring(unlocked))
         for _, recipe in ipairs(data.recipes) do
            local has_recipe = unlocked[recipe]
            if has_recipe then
               has_any_recipe = true
               if data.type == 'any' then
                  break
               end
            elseif data.type == 'all' then
               log:debug('"%s" %s doesn\'t have recipe %s', ctx.player_id, job, recipe)
               return false
            end
         end

         if not has_any_recipe then
            log:debug('"%s" %s doesn\'t have any of the checked recipes', ctx.player_id, job)
            return false
         end
      else
         log:debug('"%s" doesn\'t have job info', ctx.player_id)
         return false
      end
   end

   return true
end

return RecipesUnlockedCanStart
