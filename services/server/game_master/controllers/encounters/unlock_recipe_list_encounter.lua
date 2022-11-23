local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local job_lib = require 'stonehearth_ace.lib.job.job_lib'

local UnlockRecipeListEncounter = class()

function UnlockRecipeListEncounter:initialize()
   self._sv.ctx = nil
   self._sv.info = nil
   self._sv.recipe_bulletin = nil
end

--Unlock a recipe on the current player, as defined by the json
function UnlockRecipeListEncounter:start(ctx, info)
   assert(info.recipe_lists)
   self._sv.ctx = ctx
   self._sv.info = info

   -- unlock the recipe(s)
   self:_apply_recipe_list(info.recipe_lists)

   --create a bulletin about it!
   local bulletin_data = {
      title = info.bulletin_title,
      notification_closed_callback = '_on_closed'
   }

   self._sv.recipe_bulletin = stonehearth.bulletin_board:post_bulletin(ctx.player_id)
            :set_callback_instance(self)
            :set_sticky(true)
            :set_data(bulletin_data)

   ctx.arc:trigger_next_encounter(ctx)
end

function UnlockRecipeListEncounter:stop()
end

function UnlockRecipeListEncounter:destroy()
   local bulletin = self._sv.recipe_bulletin
   if bulletin then
      stonehearth.bulletin_board:remove_bulletin(bulletin)
      self._sv.recipe_bulletin = nil
      self.__saved_variables:mark_changed()
   end
end

function UnlockRecipeListEncounter:_apply_recipe_list(recipe_lists)
   if type(recipe_lists) == 'table' then
      for recipe_list_alias, value in pairs(recipe_lists) do
         if value == true then
            job_lib.apply_recipe_list(self._sv.ctx.player_id, recipe_list_alias)
         end
      end
   else
      assert(false, 'invalid recipe_key type. must be a table')
   end
end

function UnlockRecipeListEncounter:_destroy_node()
   self:destroy()
   game_master_lib.destroy_node(self._sv.ctx.encounter, self._sv.ctx.parent_node)
end

function UnlockRecipeListEncounter:_on_closed()
   self:_destroy_node()
end

return UnlockRecipeListEncounter