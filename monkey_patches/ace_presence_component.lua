local PresenceComponent = require 'stonehearth.components.presence.presence_component'
local AcePresenceComponent = class()

-- this will get called by the settings_call_handler whenever the setting is changed
function AcePresenceComponent:set_limit_network_data(limit_data)
   self._sv.limit_data = limit_data
   self.__saved_variables:mark_changed()
end

return AcePresenceComponent
