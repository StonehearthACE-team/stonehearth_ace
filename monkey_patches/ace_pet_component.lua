local AcePetComponent = class()

function AcePetComponent:_update_owner_description()
   local owner = self._sv.owner
   if owner and owner:is_valid() then
      -- adjust the pet's name and description to indicate that it's a pet.
      self._sv.owner_display_name = radiant.entities.get_display_name(owner)
      self._sv.owner_custom_name = radiant.entities.get_custom_name(owner)
      self._sv.owner_custom_data = radiant.entities.get_custom_data(owner)
      radiant.entities.set_description(self._entity, 'i18n(stonehearth:ui.game.pet_character_sheet.befriended_pet_description)')
      owner:add_component('stonehearth:pet_owner'):add_pet(self._entity)
   else
      self._sv.owner_display_name = nil
      self._sv.owner_custom_name = nil
      self._sv.owner_custom_data = nil
      radiant.entities.set_description(self._entity, nil)
   end
   self.__saved_variables:mark_changed()
end

return AcePetComponent
