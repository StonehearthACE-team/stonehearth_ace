local UnlockCrop = class()

function UnlockCrop:start(ctx, info)
  local farmer_job = stonehearth.job:get_job_info(ctx.player_id, 'stonehearth:jobs:farmer')
  farmer_job:manually_unlock_crop(info.crop)
end

return UnlockCrop
