-- ACE: implement smart storage filter caching

local AceNearbyItemSearch = radiant.class()

function AceNearbyItemSearch:_exhausted_ground_item_finder()
   if self._ground_item_finder then
      self._ground_item_finder:destroy()
      self._ground_item_finder = nil
   end
   
   local is_valid_storage_predicate = stonehearth.ai:filter_from_key('is_nonempty_public_storage', '', function(storage_entity)
         local storage = storage_entity:get_component('stonehearth:storage')
         return storage and storage:is_public() and not storage:is_empty()
      end)

   local process_storage = function(storage_entity)
      local found_item
      return storage_entity:get_component('stonehearth:storage'):eval_best_passing_item(self._filter_fn, function(id, item)
               if self:_add_result(item) then
                  return true
               end
            end)
      end
      
   if #self._results >= self._max_results then
      return
   end
   
   if stonehearth.ai:fast_call_filter_fn(is_valid_storage_predicate, self._entity) then
      process_storage(self._entity)
   end

   self._storage_item_finder = self:_search(self._entity, is_valid_storage_predicate, process_storage, function()
         self:_done_searching()
      end)
end

return AceNearbyItemSearch
