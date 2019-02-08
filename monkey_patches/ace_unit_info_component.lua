local UnitInfoComponent = require 'stonehearth.components.unit_info.unit_info_component'
local AceUnitInfoComponent = class()
local rng = _radiant.math.get_default_rng()

-- TODO: implement some kind of randomized naming so you can get uniquely named items from regular loot mechanics
-- perhaps limit it to items of higher-than-base quality?
-- would have to delay setting then, since that won't happen immediately on creation
-- could provide for some sort of interesting mechanic whereby "polishing" an item results in higher quality
--    and reveals the uniqueness of the item
AceUnitInfoComponent._ace_old_create = UnitInfoComponent.create
function AceUnitInfoComponent:create()
   local json = radiant.entities.get_json(self) or {}
   if json.display_name then
      self:set_display_name(json.display_name)
   end
   if json.custom_name then
      self:set_custom_name(json.custom_name, json.custom_data)
   end
   if json.description then
      self:set_description(json.description)
   end
   if json.icon then
      self:set_icon(json.icon)
   end
   if json.locked then
      self:lock(type(json.locked) == 'string' and json.locked or ':create()')
   end
   
   if self._ace_old_create then
      self:_ace_old_create()
   end
end

-- for now, only change set_custom_name to consider 'locked'
-- since this is the only thing that can be custom-set arbitrarily by the player
-- in future, perhaps extend this capability to set_description and/or set_icon
AceUnitInfoComponent._ace_old_set_custom_name = UnitInfoComponent.set_custom_name
function AceUnitInfoComponent:set_custom_name(custom_name, custom_data)
   if self._sv.locked then
      return false
   end

   self:_ace_old_set_custom_name(custom_name, self:_process_custom_data(custom_data))
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
   if (can_unlock_fn and can_unlock_fn(self._entity, self._sv.locker, unlocker))
         or (not can_unlock_fn and (not self._sv.locker or self._sv.locker == unlocker)) then
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

function AceUnitInfoComponent:_process_custom_data(custom_data)
   if not custom_data then
      return
   end

   if type(custom_data) ~= 'table' then
      return custom_data
   end

   local data = {}
   for k, v in pairs(custom_data) do
      if type(v) ~= 'table' then
         data[k] = v
      else
         if v.type == 'one_of' and type(v.items) == 'table' then
            local index = rng:get_int(1, #v.items)
            data[k] = self:_process_custom_data(v.items[index])
         else
            data[k] = v
         end
      end
   end
end

return AceUnitInfoComponent
