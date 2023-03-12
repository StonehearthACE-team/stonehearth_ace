local HumanSimpleLaborDispatcher = radiant.class()
HumanSimpleLaborDispatcher.name = 'human simple labor dispatcher'
HumanSimpleLaborDispatcher.does = 'stonehearth:work'
HumanSimpleLaborDispatcher.args = {}
HumanSimpleLaborDispatcher.priority = {0, 0.15}
HumanSimpleLaborDispatcher.disable_preemption = true  -- TODO:X: Is there a better way?

function HumanSimpleLaborDispatcher:compose_utility(entity, self_utility, child_utilities, current_activity)
   return child_utilities:get('stonehearth:simple_labor')
end

local ai = stonehearth.ai
return ai:create_compound_action(HumanSimpleLaborDispatcher)
               :execute('stonehearth:simple_labor')
