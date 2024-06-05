local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
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
      local location = radiant.entities.get_world_grid_location(self._entity)
      local root_form, iconic_form = entity_forms_lib.get_forms(self._entity)
   
      local carrying = radiant.entities.get_carrying(self._entity)
      local items = self._entity:get_component('stonehearth:storage')
      if carrying then
         radiant.entities.drop_carrying_on_ground(self._entity, location)
      end
      if items then
         items:drop_all()
      end
   
      if location and iconic_form then
         radiant.terrain.remove_entity(self._entity)
         radiant.terrain.place_entity_at_exact_location(iconic_form, location)
         radiant.effects.run_exact_effect(iconic_form, 'stonehearth:effects:fursplosion_effect')
   
         -- reset health and debuffs
         -- radiant.entities.reset_health(item, true)
      end
   end
end

function UndeploySelfWhenHurt:on_buff_removed(entity, buff)
   if self._listener then
      self._listener = nil
   end
end

return UndeploySelfWhenHurt
