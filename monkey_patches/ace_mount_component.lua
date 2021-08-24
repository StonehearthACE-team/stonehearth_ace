local log = radiant.log.create_logger('mount')

local MountComponent = require 'stonehearth.components.mount.mount_component'
local AceMountComponent = class()

AceMountComponent._ace_old_dismount = MountComponent.dismount
function AceMountComponent:dismount(set_egress_location)
   log:debug('%s dismounting (%s)...', self._entity, tostring(set_egress_location))
   return self:_ace_old_dismount(set_egress_location)
end

return AceMountComponent