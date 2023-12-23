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

function AcePetOwnerComponent:_on_pet_died(args)
   local pet = args.entity
   local pet_name = radiant.entities.get_custom_name(pet)
   local owner_name = radiant.entities.get_custom_name(self._entity)
   local species_name = stonehearth.catalog:get_catalog_data(pet:get_uri()).species_name or 'i18n(stonehearth_ace:entities.pets.pet.species)'
   local player_id = radiant.entities.get_player_id(self._entity)
   local location = radiant.entities.get_world_grid_location(pet)

   if pet_name == '' then
      pet_name = radiant.entities.get_display_name(pet)
   end

   local CUSTOMIZED_DISPLAY_NAME = "i18n(stonehearth_ace:entities.furniture.pet_urn.custom_name)"
   local CUSTOMIZED_DESCRIPTION = "i18n(stonehearth_ace:entities.furniture.pet_urn.custom_description)"

   radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:violence:pet_died', {
         tooltip_args = {
            pet_name = pet_name
         },
         context = {
            pet_id = pet:get_id()
         }
      })

   local pet_urn = radiant.entities.create_entity('stonehearth_ace:pet_urn', { owner = player_id })
   local name_component = pet_urn:add_component('stonehearth:unit_info')
   name_component:set_custom_name(pet_name, {
      owner_name = owner_name,
      pet_name = pet_name,
      species_name = species_name,
   })
   
   if pet_name:len() > 0 then
      name_component:set_display_name(CUSTOMIZED_DISPLAY_NAME)
      name_component:set_description(CUSTOMIZED_DESCRIPTION)
   else
      name_component:set_display_name(pet_name)
   end

   location = radiant.terrain.find_closest_standable_point_to(location, 5, pet_urn)
   radiant.terrain.place_entity(pet_urn, location, { force_iconic = false })
   radiant.effects.run_effect(pet_urn, 'stonehearth:effects:tombstone_effect')

   local town = stonehearth.town:get_town(player_id)
   local bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
         :set_callback_instance(town)
         :set_type('alert')
         :set_data({
            title = 'i18n(stonehearth_ace:ui.game.entities.pet_death_notification)',
            message = '',
            zoom_to_entity = pet_urn,
         })
         :add_i18n_data('entity_display_name', pet_name)
         :add_i18n_data('entity_custom_name', pet_name)
end

return AcePetOwnerComponent
