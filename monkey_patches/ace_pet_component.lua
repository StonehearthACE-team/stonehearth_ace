local PetComponent = require 'stonehearth.components.pet.pet_component'
local AcePetComponent = class()

AcePetComponent._ace_old_restore = PetComponent.restore
function AcePetComponent:restore()
   self._is_restore = true

   if self._ace_old_restore then
      self:_ace_old_restore()
   end
end

AcePetComponent._ace_old_activate = PetComponent.activate
function AcePetComponent:activate()
   -- if restoring, and we're not mounted somewhere, find a location near the town center and move there so we don't get loaded into a stuck position
   if self._is_restore then
      if radiant.entities.exists(self._sv.owner) and radiant.entities.get_world_location(self._entity) then
         local parent = radiant.entities.get_parent(self._entity)
         if not parent or not parent:get_component('stonehearth:mount') then
            local town = stonehearth.town:get_town(self._sv.owner)
            local location = town and radiant.terrain.find_placement_point(town:get_landing_location(), 0, 10)
            if location then
               radiant.terrain.place_entity(self._entity, location)
            end
         end
      end
   end
   
   self:_ace_old_activate()
end

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
