local CropCheck = class()

local log = radiant.log.create_logger('crop_check')

function CropCheck:start(ctx, info)
   local manually_unlocked = stonehearth.job:get_job_info(ctx.player_id, 'stonehearth:jobs:farmer'):get_manually_unlocked()
   local kingdom = stonehearth.population:get_population(ctx.player_id)
                                          :get_kingdom()
   local initial_crops = radiant.resources.load_json('stonehearth:farmer:initial_crops').crops_by_kingdom[kingdom]                                       
      
   if not manually_unlocked or not initial_crops then
      log:debug('could not get the farmer crops!')
      return false
   end

   if info.unknown_crop then
      for _, locked_crop in ipairs(info.unknown_crop) do
         if not manually_unlocked[locked_crop] and not initial_crops[locked_crop] then
            log:debug('looking for unknown crops: at least one crop is unknown, return true')
            return true
         end
      end
   end
   
   if info.known_crop then
      for _, unlocked_crop in ipairs(info.known_crop) do
         if not manually_unlocked[locked_crop] and not initial_crops[locked_crop] then
            log:debug('looking for known crops: at least one crop is not known, return false')
            return false
         end
      end
      return true
   end
   
   return false
end

return CropCheck