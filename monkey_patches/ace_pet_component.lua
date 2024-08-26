local rng = _radiant.math.get_default_rng()
local PetComponent = require 'stonehearth.components.pet.pet_component'
local AcePetComponent = class()

local log = radiant.log.create_logger('pet')

AcePetComponent._ace_old_restore = PetComponent.restore
function AcePetComponent:restore()
   self._is_restore = true

   if self._ace_old_restore then
      self:_ace_old_restore()
   end
   self:_update_commands()
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
      -- wait one game loop to try to self-tame, in case our owner is getting assigned by another process
      -- e.g., reembarkation
      self._self_tame_game_loop_listener = radiant.on_game_loop_once('pet self tame', function()
            self._self_tame_game_loop_listener = nil
            if not self._sv.owner and not self:self_tame() then
               self._player_id_trace = self._entity:trace_player_id('owner observer')
                  :on_changed(function()
                        if self:self_tame() then
                           self:_destroy_player_id_trace()
                        end
                     end)
            end
         end)
   end
end

AcePetComponent._ace_old_destroy = PetComponent.__user_destroy
function AcePetComponent:destroy()
   self:_destroy_player_id_trace()
   self:_destroy_self_tame_game_loop_listener()
   self:_ace_old_destroy()
end

function AcePetComponent:_destroy_player_id_trace()
   if self._player_id_trace then
      self._player_id_trace:destroy()
      self._player_id_trace = nil
   end
end

function AcePetComponent:_destroy_self_tame_game_loop_listener()
   if self._self_tame_game_loop_listener then
      self._self_tame_game_loop_listener:destroy()
      self._self_tame_game_loop_listener = nil
   end
end

function AcePetComponent:is_locked_to_owner()
   return self._sv._locked
end

function AcePetComponent:lock_to_owner()
   if self._sv.owner then
      self._sv._locked = true
      self:_update_commands()
   end
end

AcePetComponent._ace_old_convert_to_pet = PetComponent.convert_to_pet
function AcePetComponent:convert_to_pet(player_id)
   self:_ace_old_convert_to_pet(player_id)
   local wilderness_comp = self._entity:get_component('stonehearth_ace:wilderness')
   if wilderness_comp then
      wilderness_comp:set_wilderness_value(0)
   end
end

AcePetComponent._ace_old_release_pet = PetComponent.release_pet
function AcePetComponent:release_pet()
   self:_ace_old_release_pet()
   local wilderness_comp = self._entity:get_component('stonehearth_ace:wilderness')
   if wilderness_comp then
      wilderness_comp:reset_wilderness_value()
   end
end

function AcePetComponent:self_tame()
   if not radiant.entities.is_owned_by_non_npc(self._entity) then
      return false
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
   self:_update_owner_description()
   return true
end

function AcePetComponent:set_owner(owner, lock_to_owner)
   if owner ~= self._sv.owner and not self._setting_owner then
      self._setting_owner = true

      local old_owner = self._sv.owner
      self._sv.owner = owner
      self:_update_listeners()
      self:_update_owner_description()

      if old_owner and old_owner:is_valid() then
         old_owner:add_component('stonehearth:pet_owner'):remove_pet(self._entity:get_id())
      end

      if lock_to_owner then
         self:lock_to_owner()
      else
         self._sv._locked = false
         self:_update_commands()
      end

      if owner then
         radiant.events.trigger_async(self._entity, 'stonehearth:pets:adopted', { owner = owner })
      end

      self._setting_owner = false
   end
end

AcePetComponent._ace_old__set_custom_pet_name = PetComponent._set_custom_pet_name
function AcePetComponent:_set_custom_pet_name(player_id)
   if self._sv._initialized_name then
      return
   end

   if self._entity:get_component('stonehearth:unit_info') and self._entity:get_component('stonehearth:unit_info'):get_custom_name() then
      return
   end

   self._sv._initialized_name = true
   self:_ace_old__set_custom_pet_name(player_id)
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

function AcePetComponent:_update_commands()
   -- if the pet isn't locked to its owner, show the change owner command
   local commands_component = self._entity:add_component('stonehearth:commands')
   if self._sv.owner and not self._sv._locked then
      commands_component:add_command('stonehearth_ace:commands:change_pet_owner')
   else
      commands_component:remove_command('stonehearth_ace:commands:change_pet_owner')
   end
end

return AcePetComponent
