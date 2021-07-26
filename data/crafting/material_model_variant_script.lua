local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local log = radiant.log.create_logger('craft_script')
local material_model_variant = {}

function material_model_variant.on_craft(ai, crafter, workshop, recipe, ingredients, product, item, extra_products)
   if product.model_variant_material and item and item:is_valid() then
      local uri = material_model_variant.majority_material_uri(ingredients, product.model_variant_material)
      if uri then
         local root, iconic = entity_forms_lib.get_forms(item)
         if root then
            root:add_component('stonehearth_ace:entity_modification'):set_model_variant(uri)

            local loot_data = radiant.entities.get_entity_data(root, 'stonehearth_ace:variant_loot_data', false)
            if loot_data then                                
               root:add_component('stonehearth:loot_drops'):set_loot_table(loot_data[uri])
               log:detail('Adding loot table...')
            end
         end
         if iconic then
            iconic:add_component('stonehearth_ace:entity_modification'):set_model_variant(uri)
         end
         if not root and not iconic then
            item:add_component('stonehearth_ace:entity_modification'):set_model_variant(uri)
         end 
      end
   end
end

function material_model_variant.majority_material_uri(ingredients, material)
   local uri_count = {}
   for _, ingredient in pairs(ingredients) do
      local entity = entity_forms_lib.get_root_entity(ingredient) or ingredient
      if radiant.entities.is_material(entity, material) then
         local uri = entity:get_uri()
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