local LeaseComponent = require 'stonehearth.components.lease.lease_component'
local AceLeaseComponent = class()

AceLeaseComponent._ace_old_get_owner = LeaseComponent.get_owner
function AceLeaseComponent:get_owner(lease_name, allied_entity, faction)
   if not self._factions then
      return nil
   end

   return self:_ace_old_get_owner(lease_name, allied_entity, faction)
end

AceLeaseComponent._ace_old_release = LeaseComponent.release
function AceLeaseComponent:release(lease_name, entity, faction)
   if not self._factions then
      return false
   end

   return self:_ace_old_release(lease_name, entity, faction)
end

return AceLeaseComponent
