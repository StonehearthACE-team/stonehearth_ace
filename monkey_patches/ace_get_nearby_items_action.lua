local AceGetNearbyItems = radiant.class()

function AceGetNearbyItems:_consider_storage(storage_entity)
   local location = radiant.entities.get_world_grid_location(storage_entity)
   if location then
      local found_item = false
      storage_entity:get_component('stonehearth:storage'):eval_best_passing_item(self._filter_fn, function(id, item)
            if self:_add_result(item, location) then
               found_item = true
               return true
            end
         end)

      return found_item
   end
   return false
end

return AceGetNearbyItems
