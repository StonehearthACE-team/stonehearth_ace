local GeomancerClass = require 'stonehearth.jobs.geomancer.geomancer'
local CraftingJob = require 'stonehearth.jobs.crafting_job'
local AceGeomancerClass = class()
local log = radiant.log.create_logger('geomancer')

local ACE_HELPER_RECIPES = {
   ['stonehearth:jobs:cook'] = {
      'drinks:spirit_hearth',
		'animal_feed:hearth_fodder',
		'chefs_desserts:hearth_ambrosia',
   },
   ['stonehearth:jobs:herbalist'] = {
      'tonics:hearth_healing_tonic',
		'tonics:hearth_tonic',
		'farming_enhancements:hearth_fertilizer',
   },
}

function AceGeomancerClass:initialize()
   CraftingJob.__user_initialize(self)
   self._sv.max_num_golems = {}
end

AceGeomancerClass._ace_old__register_with_town = GeomancerClass._register_with_town
function AceGeomancerClass:_register_with_town()
	self:_ace_old__register_with_town()
	local player_id = radiant.entities.get_player_id(self._sv._entity)

   -- Unlock ACE recipes for other classes used by the geomancer.
   for job, recipe_keys in pairs(ACE_HELPER_RECIPES) do
      local job_info = stonehearth.job:get_job_info(player_id, job)
      for _, recipe_key in ipairs(recipe_keys) do
         job_info:manually_unlock_recipe(recipe_key)
      end
   end
end

return AceGeomancerClass
