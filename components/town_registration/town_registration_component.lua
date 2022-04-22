local TownRegistrationComponent = class()

function TownRegistrationComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._require_placement = self._json.require_placement ~= false
   self._registration_type = self._json.registration_type
end

function TownRegistrationComponent:post_activate()
   if self._registration_type then
      self._player_id = self._entity:get_player_id()
      self:_create_listeners()
      self:_consider_registering()
   end
end

function TownRegistrationComponent:destroy()
   self:_destroy_placement_listener()
   if self._player_id_changed_listener then
      self._player_id_changed_listener:destroy()
      self._player_id_changed_listener = nil
   end
   self:_unregister()
end

function TownRegistrationComponent:_create_listeners()
   self._player_id_changed_listener = self._entity:trace_player_id('town registration')
      :on_changed(function(player_id)
            self:_unregister()
            self._player_id = player_id
            self:_consider_registering()
         end)
   
   if self._require_placement then
      self._placement_listener = self._entity:add_component('mob'):trace_parent('registerable entity added or removed')
         :on_changed(function(parent_entity)
               if not parent_entity then
                  --we were just removed from the world
                  self:_unregister()
               else
                  --we were just added to the world
                  self:_consider_registering()
               end
            end)
   end
end

function TownRegistrationComponent:_destroy_placement_listener()
   if self._placement_listener then
      self._placement_listener:destroy()
      self._placement_listener = nil
   end
end

function TownRegistrationComponent:_consider_registering()
   if not self._require_placement or radiant.entities.get_world_grid_location(self._entity) then
      local town = stonehearth.town:get_town(self._player_id)
      if town then
         town:register_entity_type(self._registration_type, self._entity)
      end
   end
end

function TownRegistrationComponent:_unregister()
   local town = stonehearth.town:get_town(self._player_id)
   if town then
      town:unregister_entity_types(self._entity)
   end
end

return TownRegistrationComponent
