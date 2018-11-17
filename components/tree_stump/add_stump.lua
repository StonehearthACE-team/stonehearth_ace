local StumpComponent = class()

function StumpComponent:activate()
   self._stump_data = radiant.entities.get_entity_data(self._entity, 'stonehearth_ace:stump_data')
   if self._stump_data then
      self._on_harvest_listener = radiant.events.listen(self._entity, 'stonehearth:kill_event', function()
            self:add_stump()
            self._on_harvest_listener = nil
         end)
   end
end

function StumpComponent:destroy()
   if self._on_harvest_listener then
      self._on_harvest_listener:destroy()
      self._on_harvest_listener = nil
   end
end

function StumpComponent:add_stump()
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end
   
   --Create the entity and put it on the ground
   if not self._stump_data.stump_alias then
      return
   else
      local the_stump = radiant.entities.create_entity(self._stump_data.stump_alias, {})
      if not the_stump then
         return
      end
      radiant.terrain.place_entity_at_exact_location(the_stump, location)

      --turn it to correct rotation
      local rotation = self._entity:get_component('mob'):get_facing()
      radiant.entities.turn_to(the_stump, rotation)

      the_stump:remove_component("stonehearth_ace:add_stump")
   end
end

return StumpComponent