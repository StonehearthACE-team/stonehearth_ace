local ProjectileComponent = require 'stonehearth.components.projectile.projectile_component'
local AceProjectileComponent = class()

-- how did this get through in vanilla? they were using seconds as if they were game ticks! (off by a factor of 9/1000)
AceProjectileComponent._ace_old_get_estimated_flight_time = ProjectileComponent.get_estimated_flight_time
function AceProjectileComponent:get_estimated_flight_time()
   local seconds = self:_ace_old_get_estimated_flight_time()
   return stonehearth.calendar:realtime_to_game_seconds(seconds)
end

return AceProjectileComponent
