-- ACE: override to handle source args from event and passing them to kill_action

local Entity = _radiant.om.Entity
local DeathAction = radiant.class()

DeathAction.name = 'die'
DeathAction.does = 'stonehearth:top'
DeathAction.status_text_key = 'stonehearth:ai.actions.status_text.death'
DeathAction.args = {}
DeathAction.think_output = {
   kill_data = 'table'
}
DeathAction.version = 2
DeathAction.priority = 1.0

function DeathAction:start_thinking(ai, entity, args)
   -- What if... we were dead all along? O_O
   -- Perhaps this action wasn't thinking when the event was fired (e.g. it was being aborted?).
   local guts = radiant.entities.get_resource_percentage(entity, 'guts')
   if guts then
      if guts <= 0 then
         ai:set_think_output({
            kill_data = self._kill_data or {}
         })
         return
      end
   else
      local health = radiant.entities.get_resource_percentage(entity, 'health')
      if health and health <= 0 then
         ai:set_think_output({
            kill_data = self._kill_data or {}
         })
         return
      end
   end

   -- I'm doing science and I'm still alive.
   self._ready = false
   self._death_listener = radiant.events.listen(entity, 'stonehearth:entity:died', function(e)
         if not self._ready then
            self._kill_data = e
            ai:set_think_output({
               kill_data = self._kill_data or {}
            })
            self._ready = true
         end
      end)
end

function DeathAction:stop_thinking(ai, entity, args)
   if self._death_listener then
      self._death_listener:destroy()
      self._death_listener = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(DeathAction)
   :execute('stonehearth:die')
   :execute('stonehearth:kill_entity', {
      kill_data = ai.BACK(2).kill_data,
   })
