local HydrologyService = require 'stonehearth.services.server.hydrology.hydrology_service'
local AceHydrologyService = class()

AceHydrologyService._old_start = HydrologyService.start
function AceHydrologyService:start()
   self:_old_start()

   -- make sure the ACE water signal service is up and running (mainly a fix for stupid microworlds)
   stonehearth_ace.water_signal:start()
end

return AceHydrologyService