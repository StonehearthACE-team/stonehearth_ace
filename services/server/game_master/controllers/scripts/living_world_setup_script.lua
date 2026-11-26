local log = radiant.log.create_logger('living_world_setup')

local LivingWorldSetup = class()

function LivingWorldSetup:start(ctx, info)
   return true
end

return LivingWorldSetup