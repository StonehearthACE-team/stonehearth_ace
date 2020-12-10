local UnlockRecipeEncounter = require 'stonehearth.services.server.game_master.controllers.encounters.unlock_recipe_encounter'
local game_master_lib = require 'lib.game_master.game_master_lib'

local AceUnlockRecipeEncounter = class()

function AceUnlockRecipeEncounter:start(ctx, info)
   assert(info.job and info.recipe_key)
   self._sv.ctx = ctx
   self._sv.info = info

   local job_info = stonehearth.job:get_job_info(ctx.player_id, info.job)
   -- unlock the recipe(s)
   self:_unlock_recipes(job_info, info.recipe_key)

   --create a bulletin about it!
   if info.bulletin_title then
      local bulletin_data = {
         title = info.bulletin_title,
         notification_closed_callback = '_on_closed'
      }

      self._sv.recipe_bulletin = stonehearth.bulletin_board:post_bulletin(ctx.player_id)
            :set_callback_instance(self)
            :set_sticky(true)
            :set_data(bulletin_data)
   end

   ctx.arc:trigger_next_encounter(ctx)
end

return AceUnlockRecipeEncounter