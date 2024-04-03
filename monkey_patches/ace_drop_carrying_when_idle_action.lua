--local DropCarryingWhenIdle = require 'stonehearth.ai.actions.drop_carrying_when_idle_action'
local AceDropCarryingWhenIdle = radiant.class()

function AceDropCarryingWhenIdle:run(ai, entity, args)
   -- first do an idle breath to make sure we're not in the middle of a task
   -- (a higher priority task that had to think briefly for pathfinding or something could take over in this time)
   ai:execute('stonehearth:idle:breathe')
   ai:execute('stonehearth:drop_backpack_contents_on_ground')
end

return AceDropCarryingWhenIdle
