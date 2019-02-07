local UnitInfoComponent = require 'stonehearth.components.unit_info.unit_info_component'
local AceUnitInfoComponent = class()

-- for now, only change set_custom_name to consider 'locked'
-- since this is the only thing that can be custom-set arbitrarily by the player
-- in future, perhaps extend this capability to set_description and/or set_icon
AceUnitInfoComponent._ace_old_set_custom_name = UnitInfoComponent.set_custom_name
function AceUnitInfoComponent:set_custom_name(custom_name, custom_data)
   if self._sv.locked then
      return false
   end

   self:_ace_old_set_custom_name(custom_name, custom_data)
   return true
end

--[[
function UnitInfoComponent:set_description(custom_description)
   self._sv.description = custom_description
   self:_trigger_on_change()
end

function UnitInfoComponent:set_icon(custom_icon)
   self._sv.icon = custom_icon
   self:_trigger_on_change()
end
]]

function AceUnitInfoComponent:is_locked()
   return self._sv.locked
end

function AceUnitInfoComponent:get_locker()
   return self._sv.locker
end

-- locker can be anything: string, table, entity, whatever; most likely a string though
function AceUnitInfoComponent:lock(locker)
   if self._sv.locked then
      -- if it's already locked, it can't be locked
      return false
   end

   self._sv.locked = true
   self._sv.locker = locker
   self.__saved_variables:mark_changed()
   return true
end

-- check if the unlocker can unlock it (default equality comparison unless otherwise specified)
function AceUnitInfoComponent:unlock(unlocker, can_unlock_fn)
   if (can_unlock_fn and can_unlock_fn(self._sv.locker, unlocker))
         or (not can_unlock_fn and self._sv.locker == unlocker) then
      self:force_unlock()
      return true
   end

   return false
end

function AceUnitInfoComponent:force_unlock()
   self._sv.locked = false
   self._sv.locker = nil
   self.__saved_variables:mark_changed()
end

return AceUnitInfoComponent
