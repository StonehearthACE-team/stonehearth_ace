local CropCheck = class()

local log = radiant.log.create_logger('crop_check')

function CropCheck:start(ctx, info)
   local manually_unlocked = stonehearth.job:get_job_info(ctx.player_id, 'stonehearth:jobs:farmer'):get_manually_unlocked()
   
   if not manually_unlocked then
      log:debug('could not get the farmer job manual unlocks!')
      return false
   end

   if info.unknown_crop then
      for _, locked_crop in ipairs(info.unknown_crop) do
         if not manually_unlocked[locked_crop] then
            log:debug('looking for unknown crops: at least one crop is unknown, return true')
            return true
         end
      end
   end
   
   if info.known_crop then
      for _, unlocked_crop in ipairs(info.known_crop) do
         if not manually_unlocked[unlocked_crop] then
            log:debug('looking for known crops: at least one crop is not known, return false')
            return false
         end
      end
      return true
   end
   
   return false
end

return CropCheck