local log = radiant.log.create_logger('build.plan')

local AcePlan = class()

function AcePlan:activate()
   log:info('activating plan')
   if self._sv._current_active_node_id == 0 then
      return
   end

   local cur_node = self._sv._nodes[self._sv._current_active_node_id]
   if cur_node then
      log:info('restoring plan to %s (%s)', self._sv._current_active_node_id, cur_node.__classname)
      table.insert(self._traces, radiant.events.listen_once(cur_node, 'stonehearth:build2:plan:node_complete', self, self._advance_plan))
   end

   for idx, node in ipairs(self._sv._nodes) do
      -- ACE: also pass in whether the plan is paused
      -- fixture nodes won't have any ghosts if the plan is paused, and we don't want them to self-destruct
      node:restore(idx == self._sv._current_active_node_id, self._sv._paused)
   end
end

return AcePlan
