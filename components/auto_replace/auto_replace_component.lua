local AutoReplaceComponent = class()

function AutoReplaceComponent:initialize()
   self._json = radiant.entities.get_json(self) or {}
   self._sv._original_rotation = nil
end

function AutoReplaceComponent:activate()
   local json = self._json

   if json.on_kill ~= false then
      self._kill_listener = radiant.events.listen(self._entity, 'stonehearth:kill_event', self, self._on_kill_event)
   end
   if json.on_consume then
      
   end

   if json.reset_facing then
      self._parent_trace = self._entity:get_component('mob'):trace_parent('entity added or removed')
         :on_changed(function(parent_entity)
               if parent_entity then
                  self._sv._original_rotation = self._entity:get_component('mob'):get_facing()
                  self.__saved_variables:mark_changed()
               end
            end)
   end
end

function AutoReplaceComponent:create()
   if self._json.reset_facing then
      self._sv._original_rotation = self._entity:get_component('mob'):get_facing()
   end
end

function AutoReplaceComponent:destroy()
   self:_destroy_listeners()
end

function AutoReplaceComponent:_destroy_listeners()
   if self._kill_listener then
      self._kill_listener:destroy()
      self._kill_listener = nil
   end

   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function AutoReplaceComponent:_on_kill_event(args)
   local kill_data = args.kill_data
   local player_id = radiant.entities.get_player_id(self._entity)
   if kill_data and kill_data.source_id == player_id then
      return -- don't replace with ghost if destroyed/cleared by the user
   end
   local town = stonehearth.town:get_town(player_id)
   if town then
      local limit_data = radiant.entities.get_entity_data(self._entity:get_uri(), 'stonehearth:item_placement_limit')
      if not limit_data or town:is_placeable(limit_data) then
         local location = radiant.entities.get_world_grid_location(self._entity)
         local parent = radiant.entities.get_parent(self._entity)
         if location and parent and radiant.terrain.is_standable(self._entity, location) then -- make sure location is valid
            local placement_info = {
                  location = location,
                  normal = Point3(0, 1, 0),
                  rotation = self._sv._original_rotation or self._entity:get_component('mob'):get_facing(),
                  structure = parent,
               }
            local ghost_entity = town:place_item_type(self._entity:get_uri(), nil, placement_info)
         end
      end
   end
end

return AutoReplaceComponent