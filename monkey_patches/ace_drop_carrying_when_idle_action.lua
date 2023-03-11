--local DropCarryingWhenIdle = require 'stonehearth.ai.actions.drop_carrying_when_idle_action'
local AceDropCarryingWhenIdle = radiant.class()

--AceDropCarryingWhenIdle._ace_old_start_thinking = DropCarryingWhenIdle.start_thinking
function AceDropCarryingWhenIdle:start_thinking(ai, entity, args)
   if args.hold_position then
      return
   end

   if ai.CURRENT.carrying then
      -- if we're carrying any destroy_on_uncarry item, don't idly drop it!
      local carried_item_data = radiant.entities.get_entity_data(ai.CURRENT.carrying, 'stonehearth:item')
      if carried_item_data and carried_item_data.destroy_on_uncarry then
         return
      end
   end

   local backpack = entity:get_component('stonehearth:storage')
   local items_in_backpack = backpack and not backpack:is_empty()

   if ai.CURRENT.carrying or items_in_backpack then
      ai:set_think_output()
   end
end

return AceDropCarryingWhenIdle
