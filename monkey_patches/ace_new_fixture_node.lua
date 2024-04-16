local log = radiant.log.create_logger('build.plan.new_fixture_node')
local Fixture = 'stonehearth:build2:fixture'

local AceNewFixtureNode = class()

function AceNewFixtureNode:restore(running, paused)
   self._listeners = {}

   if not running or paused then
      return
   end
   for key, fixture in pairs(self._fixtures) do
      local ghost = radiant.entities.get_entity(fixture:get(Fixture):get_waiting_ghost_id())

      -- Unknown how this can happen (possibly an error during ghost task creation?)
      -- Since I don't know what could have happened or how to solve it, just handle
      -- this as gracefully as we can.
      if ghost then
         self._listeners[ghost:get_id()] = self:_create_listener(ghost)
      else
         self._fixtures[key] = nil
      end
   end

   -- For historical correctness only; this should never happen.
   if self:empty() then
      log:error('restoring a completed fixture node!')
      radiant.events.trigger_async(self, 'stonehearth:build2:plan:node_complete')
   end
end

return AceNewFixtureNode
