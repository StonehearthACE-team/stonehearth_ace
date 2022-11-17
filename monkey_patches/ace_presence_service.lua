local AcePresenceService = class()

function AcePresenceService:is_multiplayer()
   local presence = self._sv._presence_entity:get_component('stonehearth:presence')
   return presence._sv.is_multiplayer
end

return AcePresenceService
