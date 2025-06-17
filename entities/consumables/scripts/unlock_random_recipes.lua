--[[
   format consumable data like this:
   {
      "recipe_list": "stonehearth_ace:data:unlockable_recipes"    (alias of recipe list data file)
      "num_to_unlock": 2   (optional, defaults to 1)
   }

   format recipe list data file like this:
   {
      "first_unlocks": {
         "stonehearth:jobs:carpenter": [
            "wooden_bed_recipe"   (or whatever the recipes may be)
         ]
      },
      "stonehearth:jobs:carpenter": [
         "wooden_chair_recipe"   (or whatever the recipes may be)
      ],
      "last_unlocks": {
         "stonehearth:jobs:carpenter": [
            "wooden_stool_recipe"   (or whatever the recipes may be)
         ]
      }
   }
]]

local rng = _radiant.math.get_default_rng()
local job_lib = require 'stonehearth_ace.lib.job.job_lib'

local UnlockRandomRecipes = class()

local log = radiant.log.create_logger('unlock_random_recipes_consumable_script')

function UnlockRandomRecipes.use(consumable, consumable_data, player_id, target_entity)
   local player_job_controller = stonehearth.job:get_player_job_controller(player_id)
   if not player_job_controller then
      log:debug('no player job controller for player id "%s"', player_id)
      return false
   end

   local recipe_list = radiant.resources.load_json(consumable_data.recipe_list, true, false)
   if not recipe_list then
      log:debug('no recipe list defined')
      return false
   end

   local num_to_unlock = consumable_data.num_to_unlock or 1
   local possible_first_unlocks = {}
   local possible_recipes = {}
   local possible_last_unlocks = {}
   
   local function select_recipes(list, possible_list)
      for job, recipes in pairs(list) do
         local job_info = player_job_controller:get_job(job)

         if job_info then
            local unlocked = job_info:get_manually_unlocked()
            for _, recipe in ipairs(recipes) do
               if not unlocked[recipe] then
                  table.insert(possible_list, {job = job, recipe = recipe})
               end
            end
         end
      end
   end
   
   if recipe_list and recipe_list.first_unlocks then
      select_recipes(recipe_list.first_unlocks, possible_first_unlocks)
   end

   if recipe_list then
      select_recipes(recipe_list, possible_recipes)
   end

   if recipe_list and recipe_list.last_unlocks then
      select_recipes(recipe_list.last_unlocks, possible_last_unlocks)
   end

   -- don't consume it if there's nothing available to unlock
   if not next(possible_recipes) and not next(possible_first_unlocks) and not next(possible_last_unlocks) then
      return false
   end

   local recipes_by_job = {}
   local function unlock_recipe(unlock_list)
      num_to_unlock = num_to_unlock - 1
      local index = rng:get_int(1, #unlock_list)
      local selection = table.remove(unlock_list, index)
      local job = selection.job
      local recipes = recipes_by_job[job]
      if not recipes then
         recipes = {}
         recipes_by_job[job] = recipes
      end
      table.insert(recipes, selection.recipe)
      log:debug('selected recipe "%s" for job "%s" to unlock', selection.recipe, job)
   end

   while next(possible_first_unlocks) and num_to_unlock > 0 do
      unlock_recipe(possible_first_unlocks)
   end
      
   while next(possible_recipes) and num_to_unlock > 0 do
      unlock_recipe(possible_recipes)
   end
      
   while next(possible_last_unlocks) and num_to_unlock > 0 do
      unlock_recipe(possible_last_unlocks)
   end

   local bulletin_titles = consumable_data.bulletin_title
   job_lib.unlock_recipes(player_id, recipes_by_job, bulletin_titles, consumable_data.show_bulletin ~= false)

   return true
end

return UnlockRandomRecipes