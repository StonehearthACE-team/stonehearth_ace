local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local material_model_variant = {}

function material_model_variant.on_craft(ai, crafter, workshop, recipe, ingredients, product, item)
   if product.model_variant_material then
      local uri = material_model_variant.majority_material_uri(ingredients, product.model_variant_material)
      if uri then
         local root, iconic = entity_forms_lib.get_forms(item)
         if root then
            root:add_component('stonehearth_ace:entity_modification'):set_model_variant(uri)
         end
         if iconic then
            iconic:add_component('stonehearth_ace:entity_modification'):set_model_variant(uri)
         end
      end
   end
end

function material_model_variant.majority_material_uri(ingredients, material)
   local uri_count = {}
   for _, ingredient in pairs(ingredients) do
      if radiant.entities.is_material(ingredient, material) then
         local uri = ingredient:get_uri()
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