local CompelledCower = radiant.class()

CompelledCower.name = 'compelled cower'
CompelledCower.does = 'stonehearth:compelled_behavior'
CompelledCower.args = {}
CompelledCower.priority = 1
CompelledCower.weight = 1

function CompelledCower:start_thinking(ai, entity, args)
   if radiant.entities.is_standing_on_ladder(entity) then
      return
   end

   ai:set_think_output()
end

local ai = stonehearth.ai
return ai:create_compound_action(CompelledCower)
   :execute('stonehearth:set_posture', { posture = 'stonehearth:cower' })
   :execute('stonehearth:run_effect', { effect = 'cower', times = 20 })