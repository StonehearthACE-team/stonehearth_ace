local AceKillAtZeroHealthObserver = class()

function AceKillAtZeroHealthObserver:_on_health_changed(e)
   local health = radiant.entities.get_health(self._entity)
   if health <= 0 then
      self._listener:destroy()
      self._listener = nil
      radiant.entities.kill_entity(self._entity, {
         source_id = e.source_id or (e.source and radiant.entities.get_player_id(e.source)),
         source = e.source
      })
   end
end

return AceKillAtZeroHealthObserver
