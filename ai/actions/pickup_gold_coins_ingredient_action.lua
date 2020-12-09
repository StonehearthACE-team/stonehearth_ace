local PickupGoldCoinsIngredient = radiant.class()
PickupGoldCoinsIngredient.name = 'pickup gold coins ingredient'
PickupGoldCoinsIngredient.does = 'stonehearth:pickup_ingredient'
PickupGoldCoinsIngredient.args = {
   ingredient = 'table',                  -- what to get

   rating_fn = {                       -- a function to rate entities on a 0-1 scale to determine the best.
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}
PickupGoldCoinsIngredient.priority = 0

local GOLD_URI = 'stonehearth:loot:gold'

function PickupGoldCoinsIngredient:start_thinking(ai, entity, args)
   if args.ingredient.uri ~= GOLD_URI or not args.ingredient.min_stacks or args.ingredient.min_stacks <= 0 then
      return
   end

   self._inventory = stonehearth.inventory:get_inventory(entity)
   self._amount = args.ingredient.min_stacks

   if self:_can_pickup_gold() then
      ai:set_think_output({amount = self._amount})
   elseif self._inventory then
      self._gold_trace = self._inventory:trace_gold('crafting with gold coins')
            :on_changed(function(new_amount)
               if new_amount >= self._amount then
                  ai:set_think_output({amount = self._amount})
               end
            end)
   end
end

function PickupGoldCoinsIngredient:stop_thinking(ai, entity, args)
   if self._gold_trace then
      self._gold_trace:destroy()
      self._gold_trace = nil
   end
end

function PickupGoldCoinsIngredient:_can_pickup_gold()
   if self._inventory and self._inventory:get_gold_count() >= self._amount then
      return true
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupGoldCoinsIngredient)
               :execute('stonehearth_ace:pickup_gold_coins', {
                  amount = ai.PREV.amount
               })
