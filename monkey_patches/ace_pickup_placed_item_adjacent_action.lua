local PickupPlacedItemAdjacent = require 'stonehearth.ai.actions.pickup_placed_item_adjacent_action'
local AcePickupPlacedItemAdjacent = class()

PickupPlacedItemAdjacent.args.is_restocking = {
   type = 'boolean',
   default = false,
}

-- AcePickupPlacedItemAdjacent._ace_old_start_thinking = PickupPlacedItemAdjacent.start_thinking
-- function AcePickupPlacedItemAdjacent:start_thinking(ai, entity, args)
--    if not self:_should_pickup(args) then
--       return
--    end

--    self:_ace_old_start_thinking(ai, entity, args)
-- end

AcePickupPlacedItemAdjacent._ace_old_run = PickupPlacedItemAdjacent.run
function AcePickupPlacedItemAdjacent:run(ai, entity, args)
   -- check if it's restocking, and if so, if it should be restocked
   -- if not, then just skip it (and remove it from the ai backpack) and we'll seamlessly move on to other things
   if not self:_should_pickup(args) then
      return
   end

   self:_ace_old_run(ai, entity, args)
end

function AcePickupPlacedItemAdjacent:_should_pickup(args)
   if args.is_restocking then
      local entity_forms = args.item:get_component('stonehearth:entity_forms')
      if entity_forms and not entity_forms:get_should_restock() then
         return false
      end
   end

   return true
end

return AcePickupPlacedItemAdjacent
