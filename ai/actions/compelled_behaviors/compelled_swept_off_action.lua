local CompelledSweptOff = radiant.class()

CompelledSweptOff.name = 'compelled swept off'
CompelledSweptOff.does = 'stonehearth:unit_control'
CompelledSweptOff.args = {}
CompelledSweptOff.priority = 0
CompelledSweptOff.weight = 1

function CompelledSweptOff:start_thinking(ai, entity, args)
   if radiant.entities.is_standing_on_ladder(entity) then
      return
   end

   ai:set_think_output()
end

local ai = stonehearth.ai
return ai:create_compound_action(CompelledSweptOff)
   :execute('stonehearth:run_effect', { effect = 'sitting_idle', times = 20 })