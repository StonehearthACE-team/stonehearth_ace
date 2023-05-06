local PresenceComponent = require 'stonehearth.components.presence.presence_component'
local AcePresenceComponent = class()

-- this will get called by the settings_call_handler whenever the setting is changed
function AcePresenceComponent:set_limit_network_data(limit_data)
   self._sv.limit_data = limit_data
   self.__saved_variables:mark_changed()
end

function AcePresenceComponent:get_num_connected_players()
   if not self._sv.is_multiplayer then
      return 1
   else
      local num_connected = 0
      for player_id, data in pairs(self._sv.players) do
         if data.connection_state == stonehearth.constants.multiplayer.connection_state.CONNECTED then
            num_connected = num_connected + 1
         end
      end
      return num_connected
   end
end

return AcePresenceComponent
