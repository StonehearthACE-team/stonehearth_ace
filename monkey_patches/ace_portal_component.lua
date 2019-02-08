local PortalComponent = radiant.mods.require('stonehearth.components.portal.portal_component')
local AcePortalComponent = class()

AcePortalComponent._ace_old_activate = PortalComponent.activate
function AcePortalComponent:activate()
   if self._ace_old_activate then
      self:_ace_old_activate()
   end

   local json = radiant.entities.get_json(self) or {}
   self._horizontal = json.horizontal or false
end

function AcePortalComponent:is_horizontal()
	return self._horizontal
end

return AcePortalComponent
