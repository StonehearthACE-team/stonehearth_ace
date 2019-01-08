local PickupIngredientWithMaterial = radiant.class()
PickupIngredientWithMaterial.name = 'pickup material ingredient'
PickupIngredientWithMaterial.does = 'stonehearth:pickup_ingredient'
PickupIngredientWithMaterial.args = {
   ingredient = 'table',                  -- what to get

   rating_fn = {                       -- a function to rate entities on a 0-1 scale to determine the best.
      type = 'function',
      default = stonehearth.ai.NIL,
   },
}

PickupIngredientWithMaterial.priority = 0

function PickupIngredientWithMaterial:start_thinking(ai, entity, args)
   if args.ingredient.material ~= nil then
      ai:set_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PickupIngredientWithMaterial)
               :execute('stonehearth:pickup_item_made_of', {
                     material = ai.ARGS.ingredient.material,
                     owner_player_id = ai.ENTITY:get_player_id(),
                     rating_fn = ai.ARGS.rating_fn
                  })
