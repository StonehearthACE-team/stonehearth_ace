local AcePetOwnerComponent = class()

function AcePetOwnerComponent:remove_pet(id)
   if self._sv.pets[id] then
      self:_unlisten_for_pet_death(id)
      self._sv.pets[id] = nil
      local pet = radiant.entities.get_entity(id)
      if pet then
         pet:add_component('stonehearth:pet'):set_owner(nil)
      end
      radiant.events.trigger_async(self._entity, 'stonehearth:pets:pet_removed', { pet_id = id })
      self.__saved_variables:mark_changed()
   end
end

return AcePetOwnerComponent
