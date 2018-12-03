--local PatrollableObject = radiant.mods.require('stonehearth.services.server.town_patrol.patrollable_object')
local AcePatrollableObject = class()

function AcePatrollableObject:create(object)
   self._sv.object = object
   self._sv.object_id = object:get_id()
   self._object = self._sv.object

   if not self:get_banner() then
      self._sv.last_patrol_time = radiant.gamestate.now()
   end
end

function AcePatrollableObject:get_banner()
   return self._object:get_component('stonehearth_ace:patrol_banner')
end

return AcePatrollableObject
