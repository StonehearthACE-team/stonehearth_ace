local AceOwnableObject = class()

function AceOwnableObject:set_owner(new_owner)
   if new_owner ~= self._sv.owner then
      local previous_owner = self._sv.owner
      self:_remove_owned_object_from_owner(previous_owner)

      local add_owner = self:_add_owned_object_to_owner(new_owner)
      if not add_owner then
         self._sv.owner = nil
         self._sv.reservation_type = 'citizen'
      elseif self._sv.owner:get_component('stonehearth:traveler_reservation') or self._sv.owner:get_component('stonehearth:traveler') then
         self._sv.reservation_type = 'traveler'
      else
         local owner_proxy = self._sv.owner:get_component('stonehearth_ace:owner_proxy')
         if owner_proxy then
            self._sv.reservation_type = owner_proxy:get_type()
         else
            self._sv.reservation_type = 'citizen'
         end
      end
      stonehearth.ai:reconsider_entity(self._entity, 'owner changed')
      -- Trigger synchronously so that traveler reservations update the UI even when the game is paused
      radiant.events.trigger(self._entity, 'stonehearth:owner_changed', {new_owner = self._sv.owner})

      self.__saved_variables:mark_changed()
   end
end

function AceOwnableObject:get_reservation_type()
   return self._sv.reservation_type
end

return AceOwnableObject
