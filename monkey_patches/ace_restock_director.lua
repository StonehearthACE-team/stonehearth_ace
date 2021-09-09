local NearbyItemSearch = require 'stonehearth.services.server.inventory.nearby_item_search'
local constants = require 'stonehearth.constants'
local get_world_location = radiant.entities.get_world_location

local MAX_EXTRA_ITEMS = constants.inventory.restock_director.MAX_EXTRA_ITEMS
local AceRestockDirector = radiant.class()

-- if the item is in a storage that ignores restocking, don't add it to the queue
function AceRestockDirector:_on_item_added(item)
   if not item or not item:is_valid() then
      return
   end

   local current_storage = self._inventory:container_for(item)
   local current_storage_comp = current_storage and current_storage:get_component('stonehearth:storage')
   if current_storage_comp and current_storage_comp:get_ignore_restock() then
      return
   end

   local item_id = item:get_id()

   if not self._covered_items[item_id] and not self._failed_items[item_id] then
      self._restockable_items_queue:push(self:_rate_item(item), item)
      -- If any new errands are now possible, generate them.
      self:_mark_ready_to_generate_new_errands()
   end
end

function AceRestockDirector:_generate_next_errand()
   if not next(self._storages_by_filter) then
      return  -- We have nowhere to restock things to.
   end
   if self._active_nearby_item_search then
      return  -- We'll recurse later once we're done.
   end
   -- Check size.
   local num_errands = 0
   local max_errands = self:_get_max_errands()
   for _ in pairs(self._errands) do
      num_errands = num_errands + 1
      if num_errands >= max_errands then
         return
      end
   end

   -- Select a valid item.
   local target_item
   local best_storage, best_storage_score, filter_fn
   while self._restockable_items_queue:get_size() > 0 do
      local _, item = self._restockable_items_queue:top()
      self._restockable_items_queue:pop()
      if item:is_valid() then
         local item_id = item:get_id()

         if not self._failed_items[item_id] and not self._covered_items[item_id] and stonehearth.ai:fast_call_filter_fn(self._is_restockable_predicate, item) then
            -- Select the best storage for this item.
            for _, storage_entry in pairs(self._storages_by_filter) do
               if stonehearth.ai:fast_call_filter_fn(storage_entry.filter_fn, item) then
                  for _, storage in pairs(storage_entry.storages) do
                     local storage_component = storage:get('stonehearth:storage')
                     if storage_component and storage_component:can_reserve_space() then
                        -- ACE: also check to make sure the item isn't currently stored in an input bin of equal or greater priority
                        if self:_is_storage_higher_priority_for_item(item, storage_component) then
                           if self:_are_reachable(item, storage) then
                              local storage_score = self:_rate_storage_for_item(storage, item)
                              if not best_storage or storage_score > best_storage_score then
                                 best_storage = storage
                                 best_storage_score = storage_score
                                 filter_fn = storage_entry.filter_fn
                              end
                           end
                        end
                     end
                  end
               end
            end
            if best_storage then
               target_item = item
               break
            else
               self._failed_items[item_id] = item
               self._failed_item_queue:push(item)
            end
         end
      end
   end
   if not target_item then
      -- After a delay, requeue failed items.
      if next(self._failed_items) then
         self:_request_process_failed_items()
      end
      return
   end

   local best_storage_component = best_storage:get('stonehearth:storage')
   local best_filter_fn
   if best_storage_component:get_type() == 'input_crate' then
      local storage_priority = best_storage_component:get_input_bin_priority()
      best_filter_fn = function(item)
         if self:_is_higher_priority_for_item(item, storage_priority) then
            return filter_fn(item)
         else
            return false
         end
      end
   else
      best_filter_fn = filter_fn
   end


   -- Find nearby items that we can opportunistically include.
   local search_src_entity
   if get_world_location(target_item) then
      search_src_entity = target_item
   else
      search_src_entity = self._inventory:container_for(target_item)
   end
   local errand_id = self._current_errand_id
   local target_item_id = target_item:get_id()
   self._covered_items[target_item_id] = errand_id  -- Need to do this before the search so we don't choose this as an extra item.
   local storage_space_lease = best_storage:get_component('stonehearth:storage'):reserve_space(nil, 'restock errand')  -- Get an initial lease for one item.
   self._active_nearby_item_search = NearbyItemSearch(self._player_id, search_src_entity, best_filter_fn, self._is_restockable_predicate, self._covered_items, MAX_EXTRA_ITEMS, function(extra_items)
         local item_location = get_world_location(search_src_entity)
         if item_location and get_world_location(best_storage) then  -- The target item may have gotten moved/destroyed while we were searching.
            -- Replace the initial lease with one that also includes the extra items, if possible.
            storage_space_lease:destroy()
            local best_storage_component = best_storage:get_component('stonehearth:storage')
            if best_storage_component then  -- storage might be destroyed while searching for nearby items
               storage_space_lease = best_storage_component:reserve_space(nil, 'restock errand', 1 + radiant.size(extra_items))
               if storage_space_lease then
                  -- Create the errand.
                  self._errands[errand_id] = {
                     filter_fn = filter_fn,
                     filter_key = self._storage_filters[best_storage:get_id()],
                     main_item = target_item,
                     item_location = item_location,
                     extra_items = extra_items,
                     storage = best_storage,
                     storage_space_lease = storage_space_lease,
                  }
                  self._errands[errand_id].score = self:_rate_errand(self._errands[errand_id])

                  for _, item in pairs(extra_items) do
                     if item and item:is_valid() then
                        self._covered_items[item:get_id()] = errand_id
                     end
                  end

                  self._current_errand_id = (self._current_errand_id + 1) % 999999  -- avoid the (unlikely) float mantissa limit.

                  radiant.events.trigger_async(self, 'stonehearth:restock:errand_available', errand_id)
               end
            end
         else
            storage_space_lease:destroy()
            self._failed_items[target_item_id] = target_item
            self._failed_item_queue:push(target_item)
         end

         self._active_nearby_item_search = nil
         self:_mark_ready_to_generate_new_errands()
      end)
end

-- if the item is currently in a storage, either it doesn't match the filter or this is the input_bin restock director
-- do a quick check on whether it's properly stored to see if input bin priority checks are needed
function AceRestockDirector:_is_storage_higher_priority_for_item(item, new_storage_comp)
   local current_storage = self._inventory:container_for(item)
   local current_storage_comp = current_storage and current_storage:get_component('stonehearth:storage')
   -- not in storage, or not supposed to be in this storage
   if not current_storage or not current_storage_comp:get_passed_items()[item:get_id()] then
      return true
   end

   -- in an input crate, and destination isn't an input crate
   if current_storage_comp:get_type() == 'input_crate' and new_storage_comp:get_type() ~= 'input_crate' then
      return false
   end

   -- not in an input crate, and destination is an input crate
   if current_storage_comp:get_type() ~= 'input_crate' and new_storage_comp:get_type() == 'input_crate' then
      return true
   end

   return new_storage_comp:get_input_bin_priority() > current_storage:get_component('stonehearth:storage'):get_input_bin_priority()
end

function AceRestockDirector:_is_higher_priority_for_item(item, priority)
   local current_storage = self._inventory:container_for(item)
   if not current_storage then
      return true
   end

   return priority > current_storage:get_component('stonehearth:storage'):get_input_bin_priority()
end

function AceRestockDirector:_make_is_restockable_predicate(allow_stored)
   -- WARNING: The function we create here is a hotspot.
   -- We capture as many things as possible in upvalues for performance reasons.
   local player_id = self._player_id
   local get_player_id = radiant.entities.get_player_id
   local exists_in_world = radiant.entities.exists_in_world
   local catalog = stonehearth.catalog
   local get_catalog_data = catalog.get_catalog_data
   local inventory = self._inventory

   -- now create the filter function.  again, this function must work for
   -- *ALL* containers with the same filter key, which is why this is
   -- implemented in terms of global functions, parameters to the filter
   -- function, and captured local variables.
   local function _filter_passes(entity, allow_out_of_world_entities)
      -- TODO: If this continues to show up on the profiler, check if perhaps it's due to a cache sticking around after a restock director is deactivated.
      if not entity or not entity:is_valid() then
         return false
      end

      local storage = inventory:container_for(entity)
      if storage then
         local sc = storage:get_component('stonehearth:storage')
         local sc_type = sc:get_type()
         if sc_type ~= 'output_crate' then  -- We can always take things from output crates.
            if not sc:is_public() then
               return false  -- Don't touch my private property.
            end
            if sc:get_passed_items()[entity:get_id()] then
               if not allow_stored then
                  return false  -- Already in a storage that accepts it.
               elseif sc_type == 'input_crate' and sc:is_input_bin_highest_priority() then
                  return false  -- We don't restock from *highest priority* input crates even if we allow stored.
               end
            end
         end
      else
         if not allow_out_of_world_entities and not exists_in_world(entity) then
            return false
         end
      end

      local item_player_id = get_player_id(entity)
      if item_player_id ~= player_id then
         local task_tracker_component = entity:get_component('stonehearth:task_tracker')
         local loot_item_requested = false
         if task_tracker_component and task_tracker_component:is_task_requested(player_id, nil, 'stonehearth:loot_item') then
            loot_item_requested = true
         end

         if not loot_item_requested then
            return false
         end
      end

      local efc = entity:get_component('stonehearth:entity_forms')
      if efc then
         if not efc:get_should_restock() then
            return false
         end
         local iconic_entity = efc:get_iconic_entity()
         return _filter_passes(iconic_entity, true)
      end

      if entity:get_component('stonehearth:ghost_form') then
         return false
      end

      local entity_uri = entity:get_uri()
      local catalog_data = get_catalog_data(catalog, entity_uri)
      if not catalog_data then
         return false
      end

      if not rawget(catalog_data, 'is_item') then
         return false
      end

      if entity:get_component('stonehearth:construction_progress') then
         return false
      end

      local root_entity = entity
      local ifc = entity:get_component('stonehearth:iconic_form')
      if ifc then
         root_entity = ifc:get_root_entity() or entity
      end

      local sc = root_entity:get_component('stonehearth:storage')
      if sc then
         if not sc:is_empty() then
            return false
         end
      end

      return true
   end

   return _filter_passes
end

return AceRestockDirector
