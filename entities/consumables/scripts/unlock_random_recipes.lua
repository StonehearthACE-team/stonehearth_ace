--[[
   format consumable data like this:
   {
      "recipe_list": "stonehearth_ace:data:unlockable_recipes"    (alias of recipe list data file)
      "num_to_unlock": 2   (optional, defaults to 1)
   }

   format recipe list data file like this:
   {
      "jobs": {
         "stonehearth:jobs:carpenter": [
            "wooden_chair_recipe"   (or whatever the recipes may be)
         ]
      }
   }
]]

local rng = _radiant.math.get_default_rng()
local UnlockRandomRecipes = class()

local log = radiant.log.create_logger('unlock_random_recipes_consumable_script')

function UnlockRandomRecipes.use(consumable, consumable_data, player_id, target_entity)
   local player_job_controller = stonehearth.job:get_player_job_controller(player_id)
   if not player_job_controller then
      log:debug('no player job controller for player id "%s"', player_id)
      return
   end
    
   local recipe_list = radiant.resources.load_json(consumable_data.recipe_list, true, false)
   if not recipe_list or not recipe_list.jobs then
      log:debug('no recipe list defined')
      return
   end

   local num_to_unlock = consumable_data.num_to_unlock or 1
   local possible_recipes = {}
   
   for job, recipes in pairs(recipe_list.jobs) do
      local job_info = player_job_controller:get_job(job)
      
      if job_info then
         local unlocked = job_info:get_manually_unlocked()
         for _, recipe in ipairs(recipes) do
            if not unlocked[recipe] then
               table.insert(possible_recipes, {job_info = job_info, recipe = recipe})
            end
         end
      end
   end
   
   while next(possible_recipes) and num_to_unlock > 0 do
      num_to_unlock = num_to_unlock - 1
      local index = rng:get_int(1, #possible_recipes)
      local selection = table.remove(possible_recipes, index)
      
      selection.job_info:manually_unlock_recipe(selection.recipe)
      log:debug('unlocking %s recipe "%s"', selection.job_info:get_alias(), selection.recipe)
   end
end

return UnlockRandomRecipes