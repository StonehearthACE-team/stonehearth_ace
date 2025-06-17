local RecipesUnlockedCanStart = class()

local log = radiant.log.create_logger('recipes_unlocked_can_start')

function RecipesUnlockedCanStart:start(ctx, info)
   local player_job_controller = stonehearth.job:get_player_job_controller(ctx.player_id)
   if not player_job_controller then
      log:debug('no player job controller for player id "%s"', ctx.player_id)
      return false
   end

   local recipe_list = {}
   if info.recipe_list then
      recipe_list = radiant.resources.load_json(info.recipe_list, true, false)
   else
      recipe_list = info.jobs
   end

   local function check_job_recipes(job, recipes)
      local job_info = player_job_controller:get_job(job)
      if job_info then
         local has_any_recipe = false
         local unlocked = job_info:get_manually_unlocked()
         for _, recipe in ipairs(recipes) do
            local has_recipe = unlocked[recipe]
            if has_recipe then
               has_any_recipe = true
               if info.type == 'any' then
                  return true
               end
            elseif info.type == 'all' then
               log:debug('"%s" %s doesn\'t have recipe %s', ctx.player_id, job, recipe)
               return false
            end
         end

         if not has_any_recipe then
            log:debug('"%s" %s doesn\'t have any of the checked recipes', ctx.player_id, job)
            return false
         end
         return true
      else
         log:debug('"%s" doesn\'t have job info for "%s"', ctx.player_id, job)
         return false
      end
   end

   local function traverse_jobs(list)
      for key, value in pairs(list) do
         if type(value) == 'table' and #value > 0 then
            -- value is a recipe array, key is likely a job
            local result = check_job_recipes(key, value)
            if not result then
               return false
            elseif info.type == 'any' and result then
               return true
            end
         elseif type(value) == 'table' then
            -- recurse deeper
            local result = traverse_jobs(value)
            if not result and info.type == 'all' then
               return false
            elseif result and info.type == 'any' then
               return true
            end
         end
      end
      return info.type == 'all'
   end

   return traverse_jobs(recipe_list)
end

return RecipesUnlockedCanStart