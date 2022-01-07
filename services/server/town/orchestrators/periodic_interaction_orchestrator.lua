--[[
   Similar to craft_items_orchestrator. Observes periodic_interaction entities that register with the town,
   listening to when they're available for use, determining valid users, and creating tasks for them.
]]

local PeriodicInteractionOrchestrator

local log = radiant.log.create_logger('periodic_interaction'):set_prefix('orchestrator')

function PeriodicInteractionOrchestrator:run(town, args)
   self._town = town
   self:_setup_listeners()
end

function PeriodicInteractionOrchestrator:_setup_listeners()
   self._entity_listeners = {}
   for id, pi_entity in pairs(self._town:get_periodic_interaction_entities()) do
      self:_setup_entity_listener(pi_entity)
   end

   self._entity_added_listener = radiant.events.listen(self._town, 'stonehearth_ace:periodic_interaction:entity_added', function (entity)
         self:_setup_entity_listener(entity)
      end)
end

function PeriodicInteractionOrchestrator:_setup_entity_listener(entity)
   local id = entity:get_id()
   if not self._entity_listeners[id] then
      self._entity_listeners[id] = radiant.events.listen(entity, 'stonehearth_ace:periodic_interaction:became_usable', self, self._entity_became_usable)
   end
end

function PeriodicInteractionOrchestrator:_entity_became_usable(entity, mode)
   
end

return PeriodicInteractionOrchestrator
