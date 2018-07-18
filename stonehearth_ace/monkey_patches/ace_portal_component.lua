local PortalComponent = radiant.mods.require('stonehearth.components.portal.portal_component')
local AcePortalComponent = class()

AcePortalComponent._old_initialize = PortalComponent.initialize

function AcePortalComponent:initialize()
   self:_old_initialize()

   local json = radiant.entities.get_json(self)
   self._depth = json.depth
end

function AcePortalComponent:get_depth()
	return self._depth
end

return AcePortalComponent
