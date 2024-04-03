local ItemSearch = require 'stonehearth.components.item_finder.item_search'

local NearbyItemSearch = radiant.class()

local get_world_location = radiant.entities.get_world_location

function NearbyItemSearch:__init(player_id, src_entity, filter_fn, inclusion_filter_fn, exclusion_filter, max_results, done_cb, rating_fn)
   self._player_id = player_id
   self._entity = src_entity
   self._filter_fn = filter_fn
   self._results = {}
   self._backup_results = {}
   self._result_ids = {}
   self._done_cb = done_cb
   self._max_results = max_results
   self._inclusion_filter_fn = inclusion_filter_fn
   self._exclusion_filter = exclusion_filter
   self._rating_fn = rating_fn

   -- Start looking around us on the ground by default.
   self._ground_item_finder = self:_search(self._entity, self._filter_fn,
         function(item)
            return self:_add_result(item)
         end,
         function()
            self:_exhausted_ground_item_finder()
         end)

   -- Sometimes searches might get stuck. Time them out after a while.
   self._timeout_timer = stonehearth.calendar:set_timer('nearby item timeout', '30m', function()
         self:_done_searching()
      end)
end

function NearbyItemSearch:destroy()
   self:_cleanup()
end

function NearbyItemSearch:_exhausted_ground_item_finder()
   if self._ground_item_finder then
      self._ground_item_finder:destroy()
      self._ground_item_finder = nil
   end

   local is_valid_storage_predicate = stonehearth.ai:filter_from_key('is_nonempty_public_storage', '', function(storage_entity)
         local storage = storage_entity:get_component('stonehearth:storage')
         return storage and storage:is_public() and not storage:is_empty()
      end)

   local process_storage = function(storage_entity)
         local found_item = false
         storage_entity:get_component('stonehearth:storage'):eval_best_passing_item(self._filter_fn, function(id, item)
               if self:_add_result(item) then
                  found_item = true
                  return true
               end
            end)

         return found_item
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

function NearbyItemSearch:_search(src_entity, filter_fn, found_cb, exhausted_cb)
   local description = 'NearbyItemSearch'
   local location = get_world_location(src_entity)
   if not location then
      exhausted_cb()
      return nil
   end
   local filter_key = tostring(filter_fn)
   stonehearth.ai:create_spatial_cache(filter_fn, filter_key, description)
   local item_finder = _radiant.sim.create_item_finder(src_entity, 'ifc', description, filter_key)
            :set_source(location)
            :set_should_sort(true)
            :set_max_distance(16)
   local ignore_leases = true  -- We would need an entity otherwise.
   return ItemSearch(src_entity, item_finder, description, filter_key, ignore_leases, self._player_id)
            :add_found_cb(found_cb)
            :add_exhausted_cb(exhausted_cb)
end

function NearbyItemSearch:_add_result(item)
   local item_id = item:get_id()
   if item ~= self._entity and not self._result_ids[item_id] and not self._exclusion_filter[item_id] and
         stonehearth.ai:fast_call_filter_fn(self._inclusion_filter_fn, item) then
      self._result_ids[item_id] = true
      local rating = self._rating_fn and self._rating_fn(item)
      if not rating or rating >= 1 then
         table.insert(self._results, item)

         if #self._results >= self._max_results then
            self:_done_searching()
            return true
         end
      else
         table.insert(self._backup_results, {item = item, rating = rating})
      end
   end
   return false
end

function NearbyItemSearch:_done_searching()
   self:_cleanup()
   if self._done_cb then
      if #self._results < self._max_results then
         table.sort(self._backup_results, function(a, b)
               return a.rating > b.rating
            end)
         for _, result in ipairs(self._backup_results) do
            table.insert(self._results, result.item)
            if #self._results >= self._max_results then
               break
            end
         end
      end

      self._done_cb(self._results)
      self._done_cb = nil
   end
end

function NearbyItemSearch:_cleanup()
   if self._ground_item_finder then
      self._ground_item_finder:destroy()
      self._ground_item_finder = nil
   end
   if self._storage_item_finder then
      self._storage_item_finder:destroy()
      self._storage_item_finder = nil
   end
   if self._timeout_timer then
      self._timeout_timer:destroy()
      self._timeout_timer = nil
   end
end

return NearbyItemSearch
