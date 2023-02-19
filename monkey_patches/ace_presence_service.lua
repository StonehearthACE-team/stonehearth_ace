local AcePresenceService = class()

function AcePresenceService:is_multiplayer()
   local presence = self._sv._presence_entity:get_component('stonehearth:presence')
   return presence._sv.is_multiplayer
end

function AcePresenceService:set_limit_network_data(limit_data)
   local presence = self._sv._presence_entity:get_component('stonehearth:presence')
   presence:set_limit_network_data(limit_data)
end

return AcePresenceService
