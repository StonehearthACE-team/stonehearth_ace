--local PatrollableObject = radiant.mods.require('stonehearth.services.server.town_patrol.patrollable_object')
local AcePatrollableObject = class()

function AcePatrollableObject:get_banner()
   return self._object:get_component('stonehearth_ace:patrol_banner')
end

return AcePatrollableObject
