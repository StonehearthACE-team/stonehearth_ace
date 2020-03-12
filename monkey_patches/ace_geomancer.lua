local GeomancerClass = require 'stonehearth.jobs.geomancer.geomancer'
local CraftingJob = require 'stonehearth.jobs.crafting_job'
local AceGeomancerClass = class()
local log = radiant.log.create_logger('geomancer')

local ACE_HELPER_RECIPES = radiant.resources.load_json('stonehearth_ace:jobs:geomancer:helper_recipes')

AceGeomancerClass._ace_old__register_with_town = GeomancerClass._register_with_town
function AceGeomancerClass:_register_with_town()
    self:_ace_old__register_with_town()
    local player_id = radiant.entities.get_player_id(self._sv._entity)

   -- Unlock ACE recipes for other classes used by the geomancer.
   local helper_recipes = ACE_HELPER_RECIPES[stonehearth.population:get_population(player_id):get_kingdom()] or ACE_HELPER_RECIPES['stonehearth:kingdoms:ascendancy']
   for job, recipe_keys in pairs(helper_recipes) do
      local job_info = stonehearth.job:get_job_info(player_id, job)
      for recipe_key, value in pairs(recipe_keys) do
         if value then
            job_info:manually_unlock_recipe(recipe_key)
         end
      end
   end
end

return AceGeomancerClass