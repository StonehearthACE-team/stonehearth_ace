local FreeTimeDispatcher = radiant.class()
FreeTimeDispatcher.name = 'free time dispatcher'
FreeTimeDispatcher.does = 'stonehearth:top'
FreeTimeDispatcher.args = {}
FreeTimeDispatcher.priority = {0.05, 0.1}

function FreeTimeDispatcher:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get(0)
end

local ai = stonehearth.ai
return ai:create_compound_action(FreeTimeDispatcher)
               :execute('stonehearth:free_time')
