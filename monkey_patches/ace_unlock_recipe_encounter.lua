local UnlockRecipeEncounter = require 'stonehearth.services.server.game_master.controllers.encounters.unlock_recipe_encounter'
local game_master_lib = require 'lib.game_master.game_master_lib'
local job_lib = require 'stonehearth_ace.lib.job.job_lib'

local AceUnlockRecipeEncounter = class()

AceUnlockRecipeEncounter._ace_old__destroy = UnlockRecipeEncounter.__user_destroy
function AceUnlockRecipeEncounter:destroy()
   self:_ace_old__destroy()

   if self._sv._recipe_bulletins then
      for _, bulletin in ipairs(self._sv._recipe_bulletins) do
         stonehearth.bulletin_board:remove_bulletin(bulletin)
      end
      self._sv._recipe_bulletins = nil
   end
end

function AceUnlockRecipeEncounter:start(ctx, info)
   assert(info.job and info.recipe_key)
   self._sv.ctx = ctx
   self._sv.info = info

   local job_info = stonehearth.job:get_job_info(ctx.player_id, info.job)
   -- unlock the recipe(s)
   self._sv._recipe_bulletins = job_lib.unlock_recipes(ctx.player_id, {[info.job] = info.recipe_key}, info.bulletin_title, not info.bulletin_title, self)
   --self:_unlock_recipes(job_info, info.recipe_key)

   ctx.arc:trigger_next_encounter(ctx)
end

return AceUnlockRecipeEncounter