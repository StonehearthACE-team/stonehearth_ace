local Entity = _radiant.om.Entity

local Work = class()

Work.name = 'merchant work'
Work.does = 'stonehearth_ace:merchant:work'
Work.args = {
   stall = {
      type = Entity,
      default = stonehearth.ai.NIL
   }
}
Work.priority = 1

function Work:run(ai, entity, args)
   local at_stall, stall_location
   if args.stall then
      at_stall = true
      stall_location = radiant.entities.get_world_grid_location(args.stall)
      radiant.entities.turn_to_face(entity, args.stall)
      local merchant_component = entity:get_component('stonehearth_ace:merchant')
      --local stall_component = args.stall:get_component('stonehearth_ace:market_stall')
      merchant_component:set_up_at_stall(args.stall)
   end
   
   -- just do idle animations, which should include "look at my wares" style animations
   -- if they're working at a stall, just let them continue there forever
   -- if they're at the fire, just do a few cycles and then let them think again
   -- (maybe they've wandered away from the fire, or maybe there's now a stall available)
   local num_cycles = 0
   while at_stall or num_cycles < 5 do
      -- if something happens to the stall, exit out
      if at_stall then
         local new_stall_location = radiant.entities.get_world_grid_location(args.stall)
         if new_stall_location ~= stall_location then
            break
         end
      end

      ai:execute('stonehearth:idle', {hold_position = at_stall})
      num_cycles = num_cycles + 1
   end
end

return Work
