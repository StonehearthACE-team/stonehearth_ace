local PortalComponent = radiant.mods.require('stonehearth.components.portal.portal_component')
local AcePortalComponent = class()

AcePortalComponent._old_initialize = PortalComponent.initialize

function AcePortalComponent:initialize()
   self:_old_initialize()

   local json = radiant.entities.get_json(self) or {}
   self._horizontal = json.horizontal or false
end

function AcePortalComponent:is_horizontal()
	return self._horizontal
end

return AcePortalComponent
