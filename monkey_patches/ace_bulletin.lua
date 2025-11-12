local Bulletin = require 'stonehearth.services.server.bulletin_board.bulletin'
local AceBulletin = class()

local function _is_alert_type(t)
   return t == 'alert' or string.match(t, '^alert_')
end

function AceBulletin:get_data()
   return self._sv.data
end

function AceBulletin:set_type(type)
   local prev_type = self._sv.type
   if prev_type ~= type then
      self._sv.type = type
      if _is_alert_type(type) or _is_alert_type(prev_type) then
         stonehearth.bulletin_board:update_datastore_alerts(self._sv.id, _is_alert_type(type))
      end
      self.__saved_variables:mark_changed()
   end
   return self
end

AceBulletin._ace_old__on_remove_bulletin_timer = Bulletin._on_remove_bulletin_timer
function AceBulletin:_on_remove_bulletin_timer()
   -- (ACE) Triggering an event for the encounters that depend on bulletins to clean up appropriately when it occurs
   radiant.events.trigger_async(self, 'stonehearth:bulletin:on_remove_bulletin_timer')

   self:_ace_old__on_remove_bulletin_timer()
end

function AceBulletin:is_alert_bulletin()
   return _is_alert_type(self._sv.type)
end

return AceBulletin
