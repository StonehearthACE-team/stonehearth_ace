local GetPatrolRoute = require 'stonehearth.ai.actions.get_patrol_route_action'
local AceGetPatrolRoute = radiant.class()

AceGetPatrolRoute._old_start_thinking = GetPatrolRoute.start_thinking
function AceGetPatrolRoute:start_thinking(ai, entity, args)
   self:_old_start_thinking(ai, entity, args)

   self._party_listener = radiant.events.listen(self._entity, 'stonehearth:party:party_changed', self, self._check_for_patrol_route)
end

AceGetPatrolRoute._old_stop_thinking = GetPatrolRoute.stop_thinking
function AceGetPatrolRoute:stop_thinking(ai, entity, args)
   if self._party_listener then
      self._party_listener:destroy()
      self._party_listener = nil
   end
   
   self:_old_stop_thinking(ai, entity, args)
end

return AceGetPatrolRoute
