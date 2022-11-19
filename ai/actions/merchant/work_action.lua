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
   local merchant_component = entity:get_component('stonehearth_ace:merchant')
   local at_stall
   if args.stall and args.stall:is_valid() then
      local stall_location = radiant.entities.get_world_grid_location(args.stall)
      if stall_location then
         at_stall = true
         radiant.entities.turn_to_face(entity, args.stall)
         --local stall_component = args.stall:get_component('stonehearth_ace:market_stall')
         if merchant_component:set_up_at_stall(args.stall) then
            ai:execute('stonehearth:run_effect', { effect = 'fiddle' })
         end
      end
   end

   if merchant_component:should_depart() then
      ai:abort('should_depart')
   end

   ai:execute('stonehearth:idle', {hold_position = at_stall})
end

return Work
