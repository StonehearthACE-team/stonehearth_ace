local log = radiant.log.create_logger('mount')

local MountComponent = require 'stonehearth.components.mount.mount_component'
local AceMountComponent = class()

AceMountComponent._ace_old_mount = MountComponent.mount
function AceMountComponent:mount(user, model_variant_delay)
   if self:can_mount(user) then
      local json = radiant.entities.get_json(self) or {}
      if json.applied_buffs then
         for _, buff in ipairs(json.applied_buffs) do
            radiant.entities.add_buff(user, buff)
         end
      end
      return self:_ace_old_mount(user, model_variant_delay)
   else
      return false
   end
end

AceMountComponent._ace_old_dismount = MountComponent.dismount
function AceMountComponent:dismount(set_egress_location)
   local json = radiant.entities.get_json(self) or {}
   if json.applied_buffs then
      for _, buff in ipairs(json.applied_buffs) do
         radiant.entities.remove_buff(self._sv.user, buff)
      end
   end

   --log:debug('%s dismounting (%s)...', self._entity, tostring(set_egress_location))
   self:_ace_old_dismount(set_egress_location)
end

function AceMountComponent:get_dismount_location()
   return self._sv.saved_location
end

return AceMountComponent