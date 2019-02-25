local stacks = {}

function stacks.on_craft(ai, crafter, workshop, recipe, ingredients, product, item)
   local stacks_comp = item:get_component('stonehearth:stacks')
   if stacks_comp then 
      if product.stacks then
         stacks_comp:set_stacks(product.stacks)
      elseif product.stacks_by_ingredient then
         -- go through the ingredients and add up stacks by uri/material/default in that order
         local num_stacks = 0
         for id, ingredient in pairs(ingredients) do
            local ing_stacks = product.stacks_by_ingredient[ingredient:get_uri()] or
                              stacks._get_material_stacks(product.stacks_by_ingredient, ingredient:get_uri()) or
                              product.stacks_by_ingredient.default

            if ing_stacks then
               num_stacks = num_stacks + ing_stacks
            end
         end
         stacks_comp:set_stacks(num_stacks)
      end
   end
end

function stacks._get_material_stacks(ingredient_stacks, ingredient)
   local matched = false
   local ing_stacks = 0
   for ing, num_stacks in pairs(ingredient_stacks) do
      if radiant.entities.is_material(ingredient, ing) then
         matched = true
         ing_stacks = ing_stacks + num_stacks
      end
   end
   return matched and ing_stacks
end

return stacks