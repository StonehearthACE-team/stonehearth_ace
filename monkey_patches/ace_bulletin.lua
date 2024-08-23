local Bulletin = require 'stonehearth.services.server.bulletin_board.bulletin'
local AceBulletin = class()

function AceBulletin:get_data()
   return self._sv.data
end

AceBulletin._ace_old__on_remove_bulletin_timer = Bulletin._on_remove_bulletin_timer
function AceBulletin:_on_remove_bulletin_timer()
   -- (ACE) Triggering an event for the encounters that depend on bulletins to clean up appropriately when it occurs
   radiant.events.trigger_async(self, 'stonehearth:bulletin:on_remove_bulletin_timer')

   self:_ace_old__on_remove_bulletin_timer()
end

return AceBulletin
