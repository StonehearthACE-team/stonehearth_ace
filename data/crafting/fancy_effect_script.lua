local fancy_effect = {}

function fancy_effect.on_craft(ai, crafter, workshop, recipe, ingredients, product, item, extra_products)
   if item and item:is_valid() and ai then
      radiant.entities.pickup_item(crafter, item)
      ai:execute('stonehearth:run_effect', { effect = 'promote' })
      radiant.entities.remove_carrying(crafter)
   end
end

return fancy_effect