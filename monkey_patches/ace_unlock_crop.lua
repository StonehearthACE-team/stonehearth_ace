
local AceUnlockCrop = class()

function AceUnlockCrop.use(consumable, consumable_data, player_id, target_entity)
   local farmer_job = stonehearth.job:get_job_info(player_id, "stonehearth:jobs:farmer")
   local unlock = farmer_job and farmer_job:manually_unlock_crop(consumable_data.crop)

   if not farmer_job or unlock ~= true then
      return false
   end

   return true
end

return AceUnlockCrop