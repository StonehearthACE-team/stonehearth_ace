local Entity = _radiant.om.Entity

local DropCarryingInStockpile = radiant.class()
DropCarryingInStockpile.name = 'drop carrying in stockpile'
DropCarryingInStockpile.does = 'stonehearth:drop_carrying_in_storage'
DropCarryingInStockpile.args = {
   storage = Entity,
   ignore_missing = {
      type = 'boolean',
      default = false,
   },
}
DropCarryingInStockpile.priority = 0

function DropCarryingInStockpile:start_thinking(ai, entity, args)
   if not args.storage:get_component('stonehearth:stockpile') then
      return
   end
   ai:set_think_output()
end

local ai = stonehearth.ai
return ai:create_compound_action(DropCarryingInStockpile)
         :execute('stonehearth:choose_unreserved_point_in_destination', { entity = ai.ARGS.storage })
         :execute('stonehearth:reserve_entity_destination', { entity = ai.ARGS.storage,
                                                              location = ai.BACK(1).location })
         :execute('stonehearth:goto_location', {
               reason = 'restocking stockpile',
               stop_when_adjacent = true,
               location = ai.BACK(2).location,
            })
         :execute('stonehearth:drop_carrying_adjacent', {
            location = ai.BACK(3).location,
            ignore_missing = ai.ARGS.ignore_missing,
         })
         -- Immediately after dropping the item into the stockpile, notify it that we've added something
         -- so it can update it's "valid spaces to drop stuff" region immediately.  Waiting for a
         -- lua trace on the terrain to fire would allow additional code to run after we've unreserved the
         -- spot, but before we've marked it as occupied!
         :execute('stonehearth:call_method', {
            obj = ai.ARGS.storage:get_component('stonehearth:stockpile'),
            method = 'notify_restock_finished',
            args = { ai.BACK(4).location }
         })
