local Point3 = _radiant.csg.Point3

local AceProduceCraftedItems = radiant.class()

-- Paul: only changed two lines to pass the crafter along to the order when getting/setting progress
function AceProduceCraftedItems:run(ai, entity, args)
   self._outputs = {}
   local order_progress = args.order:get_progress(entity)   -- Paul: changed this line

   if order_progress == stonehearth.constants.crafting_status.CRAFTING then
      -- if fuel was involved, consume it
      local workshop_comp = args.workshop:get_component('stonehearth:workshop')
      if workshop_comp and workshop_comp:uses_fuel() then
         workshop_comp:consume_fuel(entity)
      end

      -- don't fully destroy the ingredients yet, we want to be able to pass them to other scripts
      local ingredients, ingredient_quality = self:_pre_destroy_ingredients(args)
      self:_add_outputs_to_bench(ai, entity, args.workshop, args.order:get_recipe(), ingredients, ingredient_quality)
      for _, item in pairs(ingredients) do
         radiant.entities.destroy_entity(item)
      end

      args.order:on_item_created()
      args.order:progress_to_next_stage(entity)  -- Paul: changed this line
   -- if this order is done crafting, but we re-entered this action, we may have gotten interrupted
   -- before the crafter was able to drop off the item, so do now if the crafted item is on the table
   elseif order_progress > stonehearth.constants.crafting_status.CRAFTING then
      local ec = args.workshop:get_component('entity_container')
      if ec and ec:num_children() > 0 then
         for _, item_on_workshop in ec:each_child() do
            table.insert(self._outputs, item_on_workshop)
         end
      end
   end

   --then, pick up every item that was crafted and put it into the crafter's ingredient pouch
   for i, item in ipairs(self._outputs) do
      assert(not radiant.entities.is_carrying(entity))
      if args.workshop:get_uri() == 'stonehearth:crafter:temporary_workbench' then
         ai:execute('stonehearth:pickup_item_adjacent', { item = item })
      else
         ai:execute('stonehearth:pickup_item_on_table_adjacent', { item = item })
      end
      local crafter_component = entity:get_component('stonehearth:crafter')
      if crafter_component then
         -- If Crafter stopped being a crafter while picking up produced products.
         -- Too bad. All the stuff will be stuck on the bench. -yshan

         crafter_component:add_carrying_to_crafting_items()
         radiant.log.write('crafter', 5, 'Putting %s with id %s into crafter pack', item, item:get_id())
      end
   end

   local appeal_component = entity:get_component('stonehearth:appeal')
   if appeal_component then
      appeal_component:add_crafting_appeal_thought()
   end
   
   args.workshop:get_component('stonehearth:workshop'):finish_crafting_progress()
end

-- also calculate and return the value-weighted quality of the ingredients
function AceProduceCraftedItems:_pre_destroy_ingredients(args)
   local ec_children = {}
   local quality = 0
   local total_value = 0
   local entity_container = args.workshop:get_component('entity_container')
   --There may not be one if there is nothing on the bench yet
   if entity_container then
      while entity_container:num_children() > 0 do
         local id, child = entity_container:first_child()
         ec_children[id] = child
         entity_container:remove_child(id)
      end
      
      for i, item in pairs(ec_children) do
         local value = math.max(1, radiant.entities.get_net_worth(item:get_uri()) or 1)
         quality = quality + radiant.entities.get_item_quality(item) * value
         total_value = total_value + value
      end
   end

   return ec_children, math.max(1, quality / math.max(1, total_value))
end

-- overriding this function to pass along the ingredients and ingredient quality to the crafter component
-- also allow extra scripting
function AceProduceCraftedItems:_add_outputs_to_bench(ai, crafter, workshop, recipe, ingredients, ingredient_quality)
   -- figure out where the outputs all go
   local location_on_workshop
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

   local crafter_component = crafter:get_component('stonehearth:crafter')

   -- create all the recipe products
   --local outputs = self:_get_outputs(crafter, workshop, recipe)
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
            -- put the items on the workshop
            each_product:add_component('mob')
                     :move_to(location_on_workshop)
            workshop:add_component('entity_container')
                     :add_child(each_product)

            radiant.entities.set_player_id(each_product, crafter)
            
            -- Make sure other people don't try to swipe our item while we are deciding to take it to storage.
            local player_id = radiant.entities.get_player_id(crafter)
            stonehearth.ai:acquire_ai_lease(each_product, crafter, 1000, player_id)

            stonehearth.inventory:get_inventory(player_id):add_item(each_product)

            table.insert(self._outputs, each_product)

            -- update crafter's statistics
            radiant.entities.increment_stat(crafter, 'quality_crafts', radiant.entities.get_item_quality(each_product))
            radiant.entities.increment_stat(crafter, 'required_level_crafts', recipe.level_requirement or 0)
            radiant.entities.increment_stat(crafter, 'totals', 'crafts')
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
      end
   end
end

return AceProduceCraftedItems
