local game_master_lib = require 'lib.game_master.game_master_lib'

local UnlockCrops = class()

function UnlockCrops:initialize()
   self._sv.ctx = nil
   self._sv.info = nil
   self._sv.unlock_bulletin = nil
end

function UnlockCrops:start(ctx, data)
   self._sv.ctx = ctx
   self._sv.data = data

   self:_unlock_crops(data.crop_keys, ctx.player_id)

   --create a bulletin about it!
   local bulletin_data = {
      title = data.bulletin_title,
      notification_closed_callback = '_on_closed'
   }

   self._sv.unlock_bulletin = stonehearth.bulletin_board:post_bulletin(ctx.player_id)
            :set_callback_instance(self)
            :set_sticky(true)
            :set_data(bulletin_data)

end

function UnlockCrops:_unlock_crops(crop_keys, player_id)
   for _, crop_key in ipairs(crop_keys) do
      stonehearth.job:get_job_info(player_id, "stonehearth:jobs:farmer"):manually_unlock_crop(crop_key, true)
   end
end

function UnlockCrops:stop()
end

function UnlockCrops:destroy()
   local bulletin = self._sv.unlock_bulletin
   if bulletin then
      stonehearth.bulletin_board:remove_bulletin(bulletin)
      self._sv.unlock_bulletin = nil
      self.__saved_variables:mark_changed()
   end
end

function UnlockCrops:_destroy_node()
   self:destroy()
   game_master_lib.destroy_node(self._sv.ctx.encounter, self._sv.ctx.parent_node)
end

function UnlockCrops:_on_closed()
   self:_destroy_node()
end

return UnlockCrops
