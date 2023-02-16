local AceTrivialDeathComponent = class()

function AceTrivialDeathComponent:_on_health_changed(e)
   local entity = self._entity
   local health = radiant.entities.get_health(entity)
   if health and health <= 0 then
      radiant.events.trigger(entity, 'stonehearth:entity:died',
      {
         source_id = e.source_id or (e.source and radiant.entities.get_player_id(e.source)),
         source = e.source
      })
   end
end

return AceTrivialDeathComponent
