local CompelledWander = radiant.class()

CompelledWander.name = 'compelled wander'
CompelledWander.does = 'stonehearth:unit_control'
CompelledWander.args = {
   hold_position = {    -- is the unit allowed to move around in the action?
      type = 'boolean',
      default = false,
   }
}
CompelledWander.priority = 0
CompelledWander.weight = 5

function CompelledWander:start_thinking(ai, entity, args)
   if not args.hold_position then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(CompelledWander)
         :execute('stonehearth:wander', { radius = 8, radius_min = 1 })
