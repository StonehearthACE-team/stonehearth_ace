local HumanWorkDispatcher = radiant.class()
HumanWorkDispatcher.name = 'human work dispatcher'
HumanWorkDispatcher.does = 'stonehearth:top'
HumanWorkDispatcher.args = {}
HumanWorkDispatcher.priority = {0.1, 0.2}

function HumanWorkDispatcher:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get(0)
end

local ai = stonehearth.ai
return ai:create_compound_action(HumanWorkDispatcher)
               :execute('stonehearth:work')
