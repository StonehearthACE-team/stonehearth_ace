local rng = _radiant.math.get_default_rng()
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
   self._json = radiant.entities.get_json(self) or {}

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

   if self._json.self_tame and not self._sv.owner then
      self:self_tame()
   end
end

function AcePetComponent:self_tame()
   if not radiant.entities.is_owned_by_non_npc(self._entity) then
      return
   end

   local player_id = radiant.entities.get_player_id(self._entity)
   
   self:convert_to_pet(player_id)

   local town = stonehearth.town:get_town(player_id)
   local citizens = town:get_citizens()

   local min_distance = radiant.math.INFINITY
   local min_citizen = nil

   for _, citizen in citizens:each() do
      local distance = radiant.entities.distance_between(self._entity, citizen)
      if not min_citizen or distance < min_distance then
         min_citizen = citizen
         min_distance = distance
      end
   end

   self:set_owner(min_citizen)
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
