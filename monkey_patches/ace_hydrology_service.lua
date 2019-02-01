local HydrologyService = require 'stonehearth.services.server.hydrology.hydrology_service'
local AceHydrologyService = class()

AceHydrologyService._old__create_tick_timer = HydrologyService._create_tick_timer
function AceHydrologyService:_create_tick_timer()
   self:_old__create_tick_timer()

   -- make sure the ACE water signal service is up and running (mainly a fix for stupid microworlds)
   stonehearth_ace.water_signal:start()
end

return AceHydrologyService