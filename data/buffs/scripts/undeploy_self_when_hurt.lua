local UndeploySelfWhenHurt = class()

function UndeploySelfWhenHurt:on_buff_added(entity, buff)
   self._entity = entity
   self._buff = buff

   self._listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:health', self, self._on_health_changed)
end

function UndeploySelfWhenHurt:_on_health_changed()
   local player_id = radiant.entities.get_player_id(self._entity)
   local health = radiant.entities.get_health_percentage(self._entity)
   if health <= 0.2 then
      local entity_forms_json = radiant.entities.get_json(self._entity:get('stonehearth:entity_forms'))
      if entity_forms_json then
         local new_entity = radiant.entities.create_entity(self._entity:get_uri(), { owner = player_id, force_iconic = true })
         local iconic_entity = new_entity:get('stonehearth:entity_forms'):get_iconic_entity()
         if iconic_entity then
            local location = radiant.entities.get_world_grid_location(self._entity)
            if location then
               radiant.entities.destroy_entity(self._entity)
               radiant.terrain.place_entity_at_exact_location(iconic_entity, location)
               radiant.effects.run_exact_effect(iconic_entity, 'stonehearth:effects:fursplosion_effect')
            end
         end
      end
   end
end

function UndeploySelfWhenHurt:on_buff_removed(entity, buff)
   if self._listener then
      self._listener = nil
   end
end

return UndeploySelfWhenHurt
