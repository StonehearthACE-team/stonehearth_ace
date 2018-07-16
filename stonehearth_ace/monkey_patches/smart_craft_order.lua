local CraftOrder = radiant.mods.require('stonehearth.components.workshop.craft_order')
local SmartCraftOrder = class()

SmartCraftOrder._ace_old_on_item_created = CraftOrder.on_item_created
-- In addition to the original on_item_created function (from craft_order.lua),
-- here it's also removing the ingredients tied to the order made from
-- the reserved ingredients.
--
function SmartCraftOrder:on_item_created()
   if self._sv.condition.type == 'make' then
      self._sv.order_list:remove_from_reserved_ingredients(self._recipe.ingredients, self._sv.id, self._sv.player_id)
   end

   self:_ace_old_on_item_created()
end

return SmartCraftOrder
