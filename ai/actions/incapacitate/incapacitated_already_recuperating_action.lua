local IncapacitatedGoToRecuperateAction = radiant.class()

IncapacitatedGoToRecuperateAction.name = 'incapacitated go to recuperate'
IncapacitatedGoToRecuperateAction.does = 'stonehearth:loop_incapacitated'
IncapacitatedGoToRecuperateAction.args = {}
IncapacitatedGoToRecuperateAction.priority = 1

function IncapacitatedGoToRecuperateAction:start_thinking(ai, entity, args)
   local incapacitation = entity:get_component('stonehearth:incapacitation')
   if incapacitation:is_rescued() then
      ai:set_think_output({})
   end
end

function IncapacitatedGoToRecuperateAction:run(ai, entity, args)
   -- don't do anything!
end

return IncapacitatedGoToRecuperateAction