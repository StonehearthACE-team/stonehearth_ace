local AceJobInfoController = class()

function AceJobInfoController:queue_order_if_possible(product_uri, amount)
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

   self._sv.order_list:request_order_of(self._sv.player_id, product_uri, amount)
   return true
end

return AceJobInfoController
