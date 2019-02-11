local material_model_variant = {}

function material_model_variant.on_craft(ai, crafter, workshop, recipe, ingredients, product, item)
   if product.model_variant_material then
      local uri = material_model_variant.majority_material_uri(ingredients, product.model_variant_material)
      if uri then
         item:add_component('stonehearth_ace:entity_modification'):set_model_variant(uri)
      end
   end
end

function material_model_variant.majority_material_uri(ingredients, material)
   local uri_count = {}
   for _, ingredient in pairs(ingredients) do
      if radiant.entities.is_material(ingredient, material) then
         uri_count[uri] = (uri_count[uri] or 0) + 1
      end
   end

   local most
   for uri, count in pairs(uri_count) do
      if not most or uri_count[uri] > uri_count[most] then
         most = uri
      end
   end

   return most
end

return material_model_variant