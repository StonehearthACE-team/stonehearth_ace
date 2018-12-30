local StumpComponent = class()

function StumpComponent:activate()
   self._stump_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:stump_data')
   if self._stump_data then
      self._on_harvest_listener = radiant.events.listen(self._entity, 'stonehearth:kill_event', function(args)
            self:add_stump(args.kill_data and args.kill_data.source_id)
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

function StumpComponent:add_stump(killer_player_id)
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

      the_stump:remove_component("stonehearth_ace:stump")

      -- if the harvesting player wants to auto-clear stumps, queue up a harvest command on the stump
      if killer_player_id and killer_player_id ~= '' then
         local should_harvest = stonehearth.client_state:get_client_gameplay_setting(killer_player_id, 'stonehearth_ace', 'auto_harvest_tree_stumps', true)
         if should_harvest then
            local resource_component = the_stump:get_component('stonehearth:resource_node')
            if resource_component then
               resource_component:request_harvest(killer_player_id)
            end
         end
      end
   end
end

return StumpComponent