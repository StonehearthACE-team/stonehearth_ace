local AceStockpileComponent = class()

function AceStockpileComponent:_add_item_to_stock(entity)
   -- THIS IS SO EXPENSIVE. Do we need to do this? -yshan assert(self:can_stock_entity(entity) and self:bounds_contain(entity))

   -- Paul: this was only printing warning messages to the log (nothing with normal log levels), so don't bother doing it!
   -- local location = radiant.entities.get_world_grid_location(entity)
   -- for id, existing in pairs(self._storage:get_passed_items()) do
   --    if radiant.entities.get_world_grid_location(existing) == location then
   --       log:warning('putting %s on top of existing item %s in stockpile (location:%s)', entity, existing, location)
   --    end
   -- end

   -- hold onto the item...
   -- Paul: if we're adding gold, do it in a gold adding way
   local gold_items = self._storage:add_gold_item(entity)
   if gold_items == false then
      self._storage:add_item(entity)
   elseif gold_items then
      entity = gold_items[next(gold_items)]
   else
      entity = nil
   end
   self._sv.stocked_items = self._storage:get_passed_items()
   self.__saved_variables:mark_changed()

   if entity then
      self:_trigger_item_added_events(entity)
   end
end

return AceStockpileComponent
