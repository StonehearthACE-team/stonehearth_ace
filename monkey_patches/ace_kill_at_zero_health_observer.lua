local AceKillAtZeroHealthObserver = class()
local log = radiant.log.create_logger('kill_at_zero_health_observer')

function AceKillAtZeroHealthObserver:_on_health_changed(e)
   local health = radiant.entities.get_health(self._entity)
   if health <= 0 then
      self._listener:destroy()
      self._listener = nil
      log:debug('killing entity %s: %s', self._entity, radiant.util.table_tostring(e))
      radiant.entities.kill_entity(self._entity, {
         source_id = e.source_id or (e.source and radiant.entities.get_player_id(e.source)),
         source = e.source
      })
   end
end

return AceKillAtZeroHealthObserver
