local AceJobInfoController = class()

function AceJobInfoController:queue_order_if_possible(product_uri, amount, building)
   -- if we can craft this product, queue it up and return true
   if not self._sv.order_list then
      return false
   end

   local recipe = self._craftable_recipes[product_uri]
   if not recipe then
      return false
   end

   if recipe.manual_unlock and not self._sv.manually_unlocked[recipe.recipe_key] then
      return false
   end

   return self._sv.order_list:request_order_of(self._sv.player_id, product_uri, amount, building)
end

function AceJobInfoController:remove_craft_orders_for_building(bid)
   if self._sv.order_list then
      self._sv.order_list:remove_craft_orders_for_building(bid)
   end
end

-- Functions for locking recipes again (Pawel)
function AceJobInfoController:manually_lock_recipe(recipe_key, ignore_missing)
   if not self._sv.recipe_list then
      radiant.verify(false, "Attempting to manually lock recipe %s when job %s does not have any recipes!", recipe_key, self._sv.alias)
      return false
   end
   local found_recipe = nil
   for category, category_data in pairs(self._sv.recipe_list) do
      if category_data.recipes then
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            if recipe_data.recipe and recipe_data.recipe.recipe_key == recipe_key then
               found_recipe = recipe_data.recipe
               break
            end
         end
      end
      if found_recipe then
         break
      end
   end
   if not found_recipe then
      if not ignore_missing then
         radiant.verify(false, "Attempting to manually lock recipe %s when job %s does not have such a recipe!", recipe_key, self._sv.alias)
      end
      return false
   end

   self._sv.manually_unlocked[recipe_key] = nil
   self.__saved_variables:mark_changed()
   
   radiant.events.trigger(radiant, 'stonehearth_ace:crafting:recipe_hidden', {recipe_data = found_recipe})

   return true
end

function AceJobInfoController:manually_lock_recipe_category(category_key, ignore_missing)
   if not self._sv.recipe_list then
      radiant.verify(false, "Attempting to manually lock recipe category %s when job %s does not have any recipes!", category_key, self._sv.alias)
      return false
   end
   local found_category = false
   for category, category_data in pairs(self._sv.recipe_list) do
      if category == category_key and category_data.recipes then
         found_category = true
         for recipe_short_key, recipe_data in pairs(category_data.recipes) do
            if recipe_data.recipe and recipe_data.recipe.recipe_key then
               self._sv.manually_unlocked[recipe_data.recipe.recipe_key] = nil
               -- radiant.events.trigger(radiant, 'stonehearth_ace:crafting:recipe_hidden', {recipe_data = recipe_data.recipe})
            end
         end
         self.__saved_variables:mark_changed()
      end
   end
   if not found_category then
      if not ignore_missing then
         radiant.verify(false, "Attempting to manually lock recipe category %s when job %s does not have such a recipe category!", category_key, self._sv.alias)
      end
      return false
   end

   return true
end

return AceJobInfoController
