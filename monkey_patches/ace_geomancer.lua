local GeomancerClass = require 'stonehearth.jobs.geomancer.geomancer'
local CraftingJob = require 'stonehearth.jobs.crafting_job'
local AceGeomancerClass = class()
local log = radiant.log.create_logger('geomancer')

local ACE_HELPER_RECIPES = radiant.resources.load_json('stonehearth_ace:jobs:geomancer:helper_recipes')

function AceGeomancerClass:_register_with_town()
    local player_id = radiant.entities.get_player_id(self._sv._entity)

   -- Enforce golem limit.
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_golems)
   end

   -- Teach the player the knowledge of Hearthbud flowers.
   stonehearth.job:get_job_info(player_id, "stonehearth:jobs:farmer"):manually_unlock_crop("earthbud", true)

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