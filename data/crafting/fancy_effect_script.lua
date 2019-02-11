local fancy_effect = {}

function fancy_effect.on_craft(ai, crafter, workshop, recipe, ingredients, product, item)
   radiant.entities.pickup_item(crafter, item)
   ai:execute('stonehearth:run_effect', { effect = 'promote' })
   radiant.entities.remove_carrying(crafter)
end

return fancy_effect