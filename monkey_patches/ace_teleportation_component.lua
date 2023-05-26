local TeleportationComponent = radiant.mods.require('stonehearth.components.teleportation.teleportation_component')

local AceTeleportationComponent = class()

AceTeleportationComponent._ace_old_set_teleported = TeleportationComponent.set_teleported
function AceTeleportationComponent:set_teleported()
   local stats_comp = self._entity:get_component('stonehearth_ace:statistics')
   if stats_comp then
      stats_comp:increment_stat('totals', 'teleportation')
   end
   self:_ace_old_set_teleported()
end

return AceTeleportationComponent
