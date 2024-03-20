local Point3 = _radiant.csg.Point3

local crafting_lib = {}

function crafting_lib.get_ingredients_and_quality(workshop)
   local ec_children = {}
   local quality = 0
   local total_value = 0
   local entity_container = workshop:get_component('entity_container')
   --There may not be one if there is nothing on the bench yet
   if entity_container then
      for id, child in entity_container:each_child() do
         ec_children[id] = child
      end

      for id, child in pairs(ec_children) do
         entity_container:remove_child(id)

         local value = math.max(1, radiant.entities.get_net_worth(child:get_uri()) or 1)
         quality = quality + radiant.entities.get_item_quality(child) * value
         total_value = total_value + value
      end
   end

   return ec_children, math.max(1, quality / math.max(1, total_value))
end

function crafting_lib.destroy_ingredients(ingredients)
   for id, item in pairs(ingredients) do
      radiant.entities.destroy_entity(item)
   end
end

function crafting_lib.craft_items(ai, crafter, workshop, recipe, ingredients, ingredient_quality)
   -- figure out where the outputs all go
   -- only adding them to the workbench if an ai is passed in (i.e., not an auto-crafter)
   local location_on_workshop
   if ai then
      local ced = radiant.entities.get_entity_data(workshop, 'stonehearth:table')
      if ced then
         local offset = ced['drop_offset']
         if offset then
            offset = Point3(offset.x, offset.y, offset.z)
            local facing = workshop:get_component('mob')
                                       :get_facing()
            location_on_workshop = offset:rotated(facing)
         end
      end
      if not location_on_workshop then
         location_on_workshop = Point3(0, 1, 0)
      end
   end

   local crafter_component = crafter:get_component('stonehearth:crafter')

   -- create all the recipe products
   local primary_product = recipe.produces[1]
   local primary_uri = primary_product and primary_product.item
   local primary_output = 0
   local all_outputs = {}
   for i, product in ipairs(recipe.produces) do
      local product_uri = product.item
      if product_uri then
         local item = crafter_component:produce_crafted_item(product_uri, recipe, ingredients, ingredient_quality)
         
         -- if the item has any extra scripts to run, do those now
         local all_products = {}
         local extra_products = {}
         if product.produce_scripts then
            for _, produce_script in ipairs(product.produce_scripts) do
               local script = radiant.mods.load_script(produce_script)
               if script and script.on_craft then
                  script.on_craft(ai, crafter, workshop, recipe, ingredients, product, item, extra_products)
               end
            end
         end

         -- check the item's validity in case a script destroyed it
         if item:is_valid() then
            table.insert(all_products, item)
         end

         for _, extra_product in ipairs(extra_products) do
            if type(extra_product) == 'string' then
               table.insert(all_products, crafter_component:produce_crafted_item(extra_product, recipe, ingredients, ingredient_quality))
            else
               table.insert(all_products, extra_product)
            end
         end

         for _, each_product in ipairs(all_products) do
            radiant.entities.set_player_id(each_product, crafter)
            local player_id = radiant.entities.get_player_id(crafter)

            -- put the items on the workshop and make sure other people don't try to swipe them while we are deciding to take it to storage.
            -- this is unnecessary for auto-crafters, which will immediately handle the products
            if ai then
               each_product:add_component('mob')
                        :move_to(location_on_workshop)
               workshop:add_component('entity_container')
                        :add_child(each_product)
               stonehearth.ai:acquire_ai_lease(each_product, crafter, 1000, player_id)

               -- update crafter's statistics
               radiant.entities.increment_stat(crafter, 'quality_crafts', radiant.entities.get_item_quality(each_product))
               radiant.entities.increment_stat(crafter, 'required_level_crafts', recipe.level_requirement or 0)
               radiant.entities.increment_stat(crafter, 'totals', 'crafts')
            end

            stonehearth.inventory:get_inventory(player_id):add_item(each_product)

            table.insert(all_outputs, each_product)
         end

         item = all_products[1]

         if item then
            radiant.effects.run_effect(item, 'stonehearth:effects:item_created')

            radiant.log.write('crafter', 5, 'Making item %s with id %s', item, item:get_id())
         else
            radiant.log.write('crafter', 5, 'Making item %s failed', product_uri)
         end

         --send event that the crafter has finished an item
         local crafting_data = {
            recipe_data = recipe,
            product = item,
            product_uri = product_uri,
         }

         radiant.events.trigger_async(crafter, 'stonehearth:crafter:craft_item', crafting_data)

         for _, prod_item in ipairs(all_products) do
            if prod_item:get_uri() == primary_uri then
               primary_output = primary_output + 1
            end
         end
      end
   end

   return primary_output, all_outputs
end

return crafting_lib
