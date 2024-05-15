local Material = require 'stonehearth.components.material.material'
local NearbyItemSearch = require 'stonehearth.services.server.inventory.nearby_item_search'
local constants = require 'stonehearth.constants'
local Point3 = _radiant.csg.Point3
local exists = radiant.entities.exists
local exists_in_world = radiant.entities.exists_in_world
local get_world_location = radiant.entities.get_world_location
local are_connected = _radiant.sim.topology.are_connected
local is_supported = radiant.terrain.is_supported
local math_min = math.min
local gamestate_now = radiant.gamestate.now

local get_item_quality = radiant.entities.get_item_quality
local FAILED_ITEM_REQUEUE_SHORT_DELAY = constants.inventory.restock_director.FAILED_ITEM_REQUEUE_SHORT_DELAY

local MAX_DISTANCE_FOR_RATING_SQ = constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH * constants.inventory.MAX_SIGNIFICANT_PATH_LENGTH
local RESERVATION_LEASE_NAME = constants.ai.RESERVATION_LEASE_NAME
local FAILED_ITEM_REQUEUE_DELAY = constants.inventory.restock_director.FAILED_ITEM_REQUEUE_DELAY
local FAILED_ITEM_REQUEUE_BATCH_SIZE = constants.inventory.restock_director.FAILED_ITEM_REQUEUE_BATCH_SIZE
local MAX_EXTRA_ITEMS = constants.inventory.restock_director.MAX_EXTRA_ITEMS
local ERRAND_CONSIDER_LEASE_DURATION_MS = constants.inventory.restock_director.ERRAND_CONSIDER_LEASE_DURATION_MS
local ITEM_RATING_CACHE_RESET_INTERVAL_SEC = constants.inventory.restock_director.ITEM_RATING_CACHE_RESET_INTERVAL_SEC
local ERRAND_VALIDITY_CACHE_EXPIRY_SEC = constants.inventory.restock_director.ERRAND_VALIDITY_CACHE_EXPIRY_SEC
local MIN_CONCURRENT_ERRAND_LIMIT = constants.inventory.restock_director.MIN_CONCURRENT_ERRAND_LIMIT
local MAX_COUNT_FOR_NOVEL_ITEMS = constants.inventory.MAX_COUNT_FOR_NOVEL_ITEMS
local MIN_COUNT_FOR_PLENTIFUL_ITEMS = constants.inventory.MIN_COUNT_FOR_PLENTIFUL_ITEMS
local INFINITY = 1000000

-- Keeps track of all restockable items for a given player and generates restock errands. Not persisted.
-- The basic idea is as follows:
-- * Keep track of all storages to be restocked (input bins have a separate RestockDirector instance).
-- * Whenever a restockable item is created or reconsidered, put it into a priority queue.
--   This queue is low-maintenance, and can contain duplicates, already-restocked items, destroyed items,
--   out of date scores, etc., and is treated as a starting point.
-- * Generate restock errands up to a given limit by:
--   * Taking an item from the queue, and verifying that it's still valid and not already being restocked.
--   * Finding the closest reachable storage that can accept it.
--   * Finding reachable nearby items that can go into the same storage.
-- * When a citizen start thinking in their execute_restock_errand action, they ask for an errand, and the director
--   selects one that's reachable and closest to the citizen, also validating and pruning errands that may have
--   become invalid. The errand is temporarily leased to that citizen, to avoid overbooking, and leased permanently
--   if they start executing it.
-- * Rinse and repeat.
local RestockDirector = radiant.class()

local log = radiant.log.create_logger('restock_director')

-- Params:
-- - inventory: the inventory to restock to.
-- - allow_stored: if true, considers items stored in non-input-crates as restockable, even if they match their container's filter. Used for input crates.
-- - storage_predicate: a function that returns whether a given entity is a valid storage to restock into.
function RestockDirector:__init(inventory, allow_stored, storage_predicate)
   -- Const data.
   self._player_id = inventory:get_player_id()
   self._inventory = inventory
   self._director_name = allow_stored and 'INPUT_BIN' or 'RESTOCK'
   self._restocked_item_tracker = self._inventory:get_item_tracker('stonehearth:restocked_item_tracker')
   self._is_storage_predicate = storage_predicate  -- Not used for caches, so no need to filter_from_key().
   self._is_restockable_predicate_key = tostring(self)  -- Important: unique for each instance, even when recreated for tests!
   self._is_restockable_predicate = stonehearth.ai:filter_from_key('restock_director', self._is_restockable_predicate_key, self:_make_is_restockable_predicate(allow_stored))
   self._normal_item_quality = stonehearth.constants.item_quality.NORMAL

   -- Primary data structures.
   self._restockable_items_queue = _radiant.queue.PriorityQueue()  -- prioritized queue of items to restock. May have already restocked items, duplicates, and out of date scores, but a good approximation.
   self._restockable_high_quality_items_queue = _radiant.queue.PriorityQueue()  -- prioritized queue of high quality items to restock. May have already restocked items, duplicates, and out of date scores, but a good approximation.
   self._failed_items = {}  -- entity_id -> Entity An array of items that failed because they are inaccessible. May contain no longer restockable items. Requeued once we run out of other items.
   self._reconsider_high_quality_items_queue = _radiant.queue.PriorityQueue()  -- prioritized queue of high quality items to be reconsidered for restocking after _restockable_high_quality_items_queue is empty, populated from _failed_items.
   self._reconsider_items_queue = _radiant.queue.PriorityQueue()  -- prioritized queue of low quality items to be reconsidered for restocking after _restockable_items_queue is empty, populated from _failed_items.
   self._reconsidering_items = {}  -- entity_id -> Entity for items that are currently in the reconsider queues
   self._covered_items = {}  -- entity_id -> errand_id for all items that are covered by currently active errands
   self._storages_by_filter = {}  -- filter_key -> { filter_fn: function, storages: entity_id -> Entity, high_quality_storages: entity_id, fullness_listeners: entity_id -> listener }
   self._storage_filters = {}  -- entity_id -> filter_key for quicker lookup on storage filter changes and validity checks.
   self._errands = {}  -- errand_id -> { main_item: Entity, extra_items: list<Entity>, storage: Entity, executor: Entity, lease_expiry: number (game time ms), filter_fn: function, filter_key: string, storage_space_lease: Destructor }

   -- Auxiliary data.
   self._started = false
   self._current_errand_id = 1
   self._generate_on_next_frame_timer = nil
   self._lease_release_listener = nil
   self._storage_listeners = {}  -- list of listeners
   self._failed_item_requeue_timer = nil
   self._item_spatial_cache = nil
   self._item_filter_finder_src_entity = nil
   self._item_filter_finder = nil
   self._active_nearby_item_search = nil
   self._item_quality_cache = {}  -- item_id -> quality (int)
   self._item_should_restock_cache = {}  -- item_id -> should_restock (bool)
   self._item_rating_cache = {}  -- item_id -> score
   self._item_rating_cache_clear_interval = nil
   self._errand_last_validated = {}  -- errand_id -> timestamp for valid errands
   self._last_success_time = stonehearth.calendar:get_elapsed_time()

   -- Set listeners for storage changes.
   table.insert(self._storage_listeners, radiant.events.listen(self._inventory, 'stonehearth:inventory:storage_added', function(e)
         self:_on_storage_added(e.storage)
      end))
   table.insert(self._storage_listeners, radiant.events.listen(self._inventory, 'stonehearth:inventory:storage_removed', function(e)
         self:_on_storage_removed(e.storage_id)
      end))
   table.insert(self._storage_listeners, radiant.events.listen(self._inventory, 'stonehearth:inventory:storage_filter_changed', function(e)
         self:_on_storage_filter_changed(e.storage)
      end))

   -- Load existing storage.
   for _, storage in pairs(self._inventory:get_all_public_storage()) do
      self:_on_storage_added(storage)
   end

   -- Whenever the first storage is added (which might have happened already above), we'll start searching for items.
   -- This is to avoid running expensive logic for NPC factions when they have no storages to restock to (most of the time).
end

function RestockDirector:destroy()
   self:_ensure_stopped()
   for _, listener in ipairs(self._storage_listeners) do
      listener:destroy()
   end
   self._storage_listeners = {}
   if self._item_filter_finder then
      self._item_filter_finder:destroy()
      self._item_filter_finder = nil
   end
   if self._active_nearby_item_search then
      self._active_nearby_item_search:destroy()
      self._active_nearby_item_search = nil
   end
   if self._failed_item_requeue_timer then
      self._failed_item_requeue_timer:destroy()
      self._failed_item_requeue_timer = nil
   end
   if self._generate_on_next_frame_timer then
      self._generate_on_next_frame_timer:destroy()
      self._generate_on_next_frame_timer = nil
   end
end

function RestockDirector:get_errand(errand_id)
   return self._errands[errand_id]
end

function RestockDirector:take_errand_to_consider(entity, maybe_errand_id)
   -- Find the best errand for this entity.
   local entity_location = get_world_location(entity)

   local best_errand_id, best_score
   local consider_errand = function(errand_id, errand)
      local is_leased = errand.executor and errand.executor ~= entity and (not errand.lease_expiry or errand.lease_expiry > gamestate_now())
      if not is_leased then
         -- Must check validity first, since if the item is no longer in the world, the errand will never match and will hang around forever.
         -- TODO: Maybe this is too expensive, and we should instead do it in the action's start()?
         if self:_is_errand_valid(errand_id, errand) then
            -- Errands can become invalid if topology or items have changed since they were created, so prune them while we are here.
            if self:_are_reachable(errand.main_item, entity) then
               -- The entity can reach the item, and therefore also the storage. This errand is valid for this executor.
               local score = self:_rate_errand_for_entity_location(errand, entity_location)
               if not best_errand_id or score > best_score then
                  best_errand_id = errand_id
                  best_score = score
               end
            end
         else
            self:_on_errand_failed(errand_id)
         end
      end
   end

   if maybe_errand_id then
      -- Asking for a specific errand.
      local errand = self._errands[maybe_errand_id]
      if not errand then
         return nil
      end
      consider_errand(maybe_errand_id, errand)
   else
      -- Asking us to choose the errand.
      for errand_id, errand in pairs(self._errands) do
         consider_errand(errand_id, errand)
      end
   end

   if best_errand_id then
      local errand = self._errands[best_errand_id]
      errand.executor = entity
      errand.lease_expiry = gamestate_now() + ERRAND_CONSIDER_LEASE_DURATION_MS
      return best_errand_id, errand, best_score
   else
      return nil
   end
end

function RestockDirector:give_up_on_errand(entity, errand_id)
   local errand = self._errands[errand_id]
   if errand and errand.executor == entity then
      errand.executor = nil
      errand.lease_expiry = nil
      radiant.events.trigger_async(self, 'stonehearth:restock:errand_available', errand_id)
   end
end

function RestockDirector:mark_errand_failed(errand_id)
   if self._errands[errand_id] then
      self:_on_errand_failed(errand_id)
   end
end

-- ACE: track the items in the errand for whether they should no longer be restocked
function RestockDirector:try_start_errand(entity, errand_id)
   local errand = self._errands[errand_id]

   if not errand or (errand.executor and errand.executor ~= entity and not errand.lease_expiry) then
      -- Someone else has grabbed it already.
      return false
   else
      errand.executor = entity
      errand.lease_expiry = nil

      self:_track_should_restock_status(errand)

      radiant.events.trigger_async(self, 'stonehearth:restock:errand_started', errand_id, entity)
      return true
   end
end

function RestockDirector:_track_should_restock_status(errand)
   local items = { errand.main_item }
   for _, item in ipairs(errand.extra_items) do
      table.insert(items, item)
   end

   local entity_forms = {}
   for _, item in ipairs(items) do
      local entity_forms_component = item:get_component('stonehearth:entity_forms')
      if entity_forms_component then
         entity_forms[item:get_id()] = entity_forms_component
      else
         -- if any of them don't have entity forms, then we don't need listeners because that one can't be canceled
         return
      end
   end

   errand.should_restock = {}
   errand.should_restock_listeners = {}

   for _, item in ipairs(items) do
      local item_id = item:get_id()
      local entity_forms_component = entity_forms[item_id]

      errand.should_restock[item_id] = entity_forms_component:get_should_restock()
      errand.should_restock_listeners[item_id] = radiant.events.listen(item, 'stonehearth_ace:reconsider_restock', function()
            if radiant.entities.get_world_grid_location(item) == nil then
               -- if it's no longer in the world, don't bother listening on this errand anymore
               self:_destroy_should_restock_status_trackers(errand)
            else
               -- if it should be restocked and wasn't just picked up
               errand.should_restock[item_id] = entity_forms_component:get_should_restock() or nil
               if not next(errand.should_restock) then
                  -- if none are left, cancel the errand
                  self:mark_errand_failed(errand.id)
               end
            end
         end)
   end
end

function RestockDirector:_destroy_should_restock_status_trackers(errand)
   if errand and errand.should_restock_listeners then
      for _, listener in pairs(errand.should_restock_listeners) do
         listener:destroy()
      end
      errand.should_restock_listeners = nil
   end
end

-- ACE: also consider the main item as maybe not picked up
function RestockDirector:finish_errand(entity, errand_id)
   local errand = self._errands[errand_id]

   if not errand then
      -- Unclear how this happens, but seen in the wild.
      return
   end

   self._errands[errand_id] = nil
   self._errand_last_validated[errand_id] = nil

   self:_destroy_should_restock_status_trackers(errand)

   errand.storage_space_lease:destroy()

   -- Mark items no longer covered.
   if exists(errand.main_item) then
      -- We could keep IDs in the errand block so we can clean the covered set even if the item is destroyed, but that doesn't affect correctness.
      local main_item_id = errand.main_item:get_id()
      self._covered_items[main_item_id] = nil
      self:_on_item_added(errand.main_item)
   end
   for _, item in ipairs(errand.extra_items) do
      if exists(item) then
         local item_id = item:get_id()
         self._covered_items[item_id] = nil
         self:_on_item_added(item)  -- In case some of the extra items weren't picked up.
      end
   end

   self:_mark_ready_to_generate_new_errands()

   self._last_success_time = stonehearth.calendar:get_elapsed_time()
end

function RestockDirector:has_items_in_queue()
   return self._restockable_high_quality_items_queue:get_size() > 0 or self._restockable_items_queue:get_size() > 0 or
         next(self._reconsidering_items) ~= nil or next(self._failed_items) ~= nil
end

function RestockDirector:get_last_success_time()
   return self._last_success_time
end

function RestockDirector:_ensure_started()
   if self._started then
      return
   end

   assert(not self._item_spatial_cache)
   assert(not self._item_filter_finder_src_entity)
   assert(not self._item_filter_finder)
   assert(not self._lease_release_listener)

   -- Watch for restockable items.
   self._item_spatial_cache = stonehearth.ai:create_spatial_cache(self._is_restockable_predicate, self._is_restockable_predicate_key, 'restock_director')
   -- LAME: We need a source entity to schedule searches, so we create a fake one.
   -- MORE LAME: If we create a transient entity, it's immediately destroyed after being created on savegame load, so we have to make a new URI.
   self._item_filter_finder_src_entity = radiant.entities.create_entity('stonehearth:object:anchor', { debug_text = 'restock director search source' })
   radiant.terrain.place_entity_at_exact_location(self._item_filter_finder_src_entity, Point3(0, 0, 0))
   self._item_filter_finder = _radiant.sim.create_item_filter_finder(self._item_filter_finder_src_entity, self._is_restockable_predicate_key)
      :set_added_cb(function(e)
            self:_on_item_added(e, true)
         end)
      :set_reappraise_cb(function(e)
            self:_on_item_added(e)
         end)
      :start()

   -- When an item becomes available for interaction, see if we can schedule it (maybe again).
   self._lease_release_listener = radiant.events.listen(radiant, 'stonehearth:lease_released', function(e)
         local entity = radiant.entities.get_entity(e.entity_id)
         if entity and entity:is_valid() and e.lease_name == RESERVATION_LEASE_NAME and stonehearth.ai:fast_call_filter_fn(self._is_restockable_predicate, entity) then
            self:_on_item_added(entity)
         end
      end)

   -- Items already inside crates (or any non-stockpile storage) won't be found by the search, so load these in now.
   for _, item in pairs(self._inventory:get_all_items()) do
      if not exists_in_world(item) then
         self:_on_item_added(item, true)
      end
   end

   self._item_rating_cache_clear_interval = radiant.set_realtime_interval('clear item rating cache', ITEM_RATING_CACHE_RESET_INTERVAL_SEC * 1000.0, function()
         self._item_rating_cache = {}
      end)

   self._started = true
end

function RestockDirector:_ensure_stopped()
   if not self._started then
      return
   end

   assert(self._item_spatial_cache)
   assert(self._item_filter_finder_src_entity)
   assert(self._item_filter_finder)
   assert(self._lease_release_listener)

   self._started = false

   self._lease_release_listener:destroy()
   self._lease_release_listener = nil

   self._item_filter_finder:destroy()
   self._item_filter_finder = nil

   radiant.entities.destroy_entity(self._item_filter_finder_src_entity)
   self._item_filter_finder_src_entity = nil

   self._item_spatial_cache:destroy()  -- This is currently a no-op, since caches are immortal. We need to fix this someday.
   self._item_spatial_cache = nil

   self._item_rating_cache_clear_interval:destroy()
   self._item_rating_cache_clear_interval = nil
end

function RestockDirector:_mark_ready_to_generate_new_errands()
   if not self._generate_on_next_frame_timer then
      self._generate_on_next_frame_timer = radiant.on_game_loop_once('generate next restock errand', function()
            self._generate_on_next_frame_timer = nil
            self:_generate_next_errand()
         end)
   end
end

-- ACE: if the item is in a storage that ignores restocking, don't add it to the queue
function RestockDirector:_on_item_added(item, is_first_time)
   if not item or not item:is_valid() then
      return
   end

   if is_first_time then
      local iconic_form_comp = item:get_component('stonehearth:iconic_form')
      local root_form = iconic_form_comp and iconic_form_comp:get_root_entity() or item
      if radiant.entities.is_material(root_form, 'no_restock') then
         return
      end
   end

   local current_storage = self._inventory:container_for(item)
   local current_storage_comp = current_storage and current_storage:get_component('stonehearth:storage')
   if current_storage_comp and current_storage_comp:get_ignore_restock() then
      return
   end

   local item_id = item:get_id()

   if not self._covered_items[item_id] and not self._failed_items[item_id] and not self._reconsidering_items[item_id] then
      local rating = self:_rate_item(item, true, is_first_time)
      --log:debug('Adding item %s to restock queue with rating %s', item, rating)
      if self._item_quality_cache[item_id] then
         self._restockable_high_quality_items_queue:push(rating, item)
      else
         self._restockable_items_queue:push(rating, item)
      end
      -- If any new errands are now possible, generate them.
      self:_mark_ready_to_generate_new_errands()
   end
end

function RestockDirector:_on_storage_added(storage_entity)
   local storage = storage_entity:get('stonehearth:storage')
   if not self._is_storage_predicate(storage) then
      return
   end

   local storage_id = storage_entity:get_id()

   if self._storage_filters[storage_id] then
      -- Unclear how this can happen, but seen in the wild.
      self:_on_storage_removed(storage_id)
   end

   local filter = storage:get_filter()
   local filter_key = self:_filter_to_key(filter)
   self._storage_filters[storage_id] = filter_key

   local entry = self._storages_by_filter[filter_key]
   local prioritize_high_quality = storage:get_prioritize_restocking_high_quality()
   if not entry then
      entry = {
         filter_fn = stonehearth.ai:filter_from_key('stonehearth:restock_director', filter_key, self:_filter_to_filter_fn(filter)),
         storages = {},
         high_quality_storages = {},
         fullness_listeners = {},
      }
      self._storages_by_filter[filter_key] = entry
   end
   if prioritize_high_quality then
      entry.high_quality_storages[storage_id] = storage_entity
   else
      entry.storages[storage_id] = storage_entity
   end

   entry.fullness_listeners[storage_id] = radiant.events.listen(storage_entity, 'stonehearth:storage:fullness_changed', function(is_full)
            if is_full then
               -- Can't use this storage anymore, so cancel any errands for it.
               for errand_id, errand in pairs(self._errands) do
                  if errand.storage == storage_entity then
                     self:_on_errand_failed(errand_id)
                  end
               end
            end
         end)

   -- Requeue failed items that match the new filter, in case they are viable now.
   local filter_fn = self._storages_by_filter[filter_key].filter_fn

   for item_id, item in pairs(self._reconsidering_items) do
      if stonehearth.ai:fast_call_filter_fn(filter_fn, item) then
         self._reconsidering_items[item_id] = nil
         self:_on_item_added(item)
      end
   end

   for item_id, item in pairs(self._failed_items) do
      if stonehearth.ai:fast_call_filter_fn(filter_fn, item) then
         self._failed_items[item_id] = nil
         self:_on_item_added(item)
      end
   end

   -- Some old errands may become imperfect now, but for simplicity, let them complete for now.

   -- If any new errands are now possible, generate them.
   self:_ensure_started()
   self:_mark_ready_to_generate_new_errands()
end

function RestockDirector:_on_storage_removed(storage_id)
   if self._storage_filters[storage_id] then
      self._storage_filters[storage_id] = nil
      for filter_key, entry in pairs(self._storages_by_filter) do
         if entry.storages[storage_id] or entry.high_quality_storages[storage_id] then
            entry.storages[storage_id] = nil
            entry.high_quality_storages[storage_id] = nil
            entry.fullness_listeners[storage_id]:destroy()
            entry.fullness_listeners[storage_id] = nil
            if not next(entry.storages) and not next(entry.high_quality_storages) then
               self._storages_by_filter[filter_key] = nil
            end
         end
      end
   end
   -- Some old errands may be invalid now, but for simplicity, let them fail on their own for now.

   if not next(self._storages_by_filter) then
      self:_ensure_stopped()
   end
end

function RestockDirector:_on_storage_filter_changed(storage)
   -- This is probably too rare to matter, but could be optimized by:
   -- 1. Inlining the two parts and sharing commonalities.
   -- 2. Deduping events, since when a storage is created, its filter is also immediately set.
   if not storage or not storage:is_valid() then
      return
   end
   self:_on_storage_removed(storage:get_id())
   self:_on_storage_added(storage)
end

function RestockDirector:_transfer_reconsider_items_into_restockable_queue(reconsider, restockable)
   -- only transfer if the restockable queue is empty
   if restockable:get_size() == 0 and reconsider:get_size() > 0 then
      local remaining_item_attempts = FAILED_ITEM_REQUEUE_BATCH_SIZE
      while reconsider:get_size() > 0 and remaining_item_attempts > 0 do
         local _, item = reconsider:top()
         reconsider:pop()
         if item and item:is_valid() then
            local item_id = item:get_id()
            self._reconsidering_items[item_id] = nil
            local rating = self:_rate_item(item)
            restockable:push(rating, item)
            remaining_item_attempts = remaining_item_attempts - 1
         end
      end
      return true
   end
end

function RestockDirector:_transfer_failed_items_into_reconsider_queues()
   if next(self._failed_items) then
      for item_id, item in pairs(self._failed_items) do
         if item:is_valid() then
            local rating = self:_rate_item(item)
            if self._item_quality_cache[item_id] then
               self._reconsider_high_quality_items_queue:push(rating, item)
            else
               self._reconsider_items_queue:push(rating, item)
            end
            self._reconsidering_items[item_id] = item
         end
      end
      self._failed_items = {}
      return true
   end
end

function RestockDirector:_request_process_failed_items(delay)
   if self._failed_item_requeue_timer then
      return
   end

   -- ACE: if no errands currently, use short delay, otherwise use longer delay
   delay = delay or (next(self._errands) and FAILED_ITEM_REQUEUE_DELAY) or FAILED_ITEM_REQUEUE_SHORT_DELAY
   self._failed_item_requeue_timer = stonehearth.calendar:set_timer('requeue failed restock items', delay, function()
      self._failed_item_requeue_timer = nil

      local next_delay = next(self._errands) and FAILED_ITEM_REQUEUE_DELAY or FAILED_ITEM_REQUEUE_SHORT_DELAY
      -- first check to see if there are still any items in the reconsider queue that need to be batched into the main queue
      if self:_transfer_reconsider_items_into_restockable_queue(self._reconsider_high_quality_items_queue, self._restockable_high_quality_items_queue) or
            self:_transfer_reconsider_items_into_restockable_queue(self._reconsider_items_queue, self._restockable_items_queue) then
         --log:debug('%s transferred items from reconsider queue into restockable queue', self._director_name)
         self:_mark_ready_to_generate_new_errands()
      elseif self:_transfer_failed_items_into_reconsider_queues() then
         -- if instead we had to repopulate those queues from the failed items, then we need to try again quickly,
         -- so make sure we're using the short delay
         next_delay = FAILED_ITEM_REQUEUE_SHORT_DELAY
         --log:debug('%s transferred items from failed items into reconsider queues', self._director_name)
      else
         return
      end

      self:_request_process_failed_items(next_delay)
   end)
end

-- ACE: find the first high quality item that's restockable in a high quality storage (and the first for a low quality storage, as backup)
-- as soon as we find a high quality one, we're done
-- then find the first low quality item that's restockable in a low quality storage (and the first for a high quality storage, as backup)
-- as soon as we find a low quality one, we're done
-- if we can't find a high/high or a low/low, return the high quality item for a low quality storage, next the reverse
function RestockDirector:_get_next_restockable_item()
   local primary_item, hq_item_for_lq, lq_item_for_hq
   local requeuable_items = {}
   local temp_failed = {}
   while self._restockable_high_quality_items_queue:get_size() > 0 do
      local _, item = self._restockable_high_quality_items_queue:top()
      self._restockable_high_quality_items_queue:pop()

      local best_storage, filter_fn = self:_eval_item_for_restocking(item, true, requeuable_items)
      if best_storage then
         -- we found a high quality item for a high quality storage; just use this
         --log:debug('%s found high quality item for high quality storage: %s, %s', self._director_name, item, best_storage)
         primary_item = { item, best_storage, filter_fn }
         break
      end

      if not hq_item_for_lq then
         best_storage, filter_fn = self:_eval_item_for_restocking(item, false, temp_failed)
         if best_storage then
            hq_item_for_lq = { item, best_storage, filter_fn }
         end
      end
   end

   if not primary_item then
      while self._restockable_items_queue:get_size() > 0 do
         local _, item = self._restockable_items_queue:top()
         self._restockable_items_queue:pop()

         local best_storage, filter_fn = self:_eval_item_for_restocking(item, true, requeuable_items)
         if best_storage then
            -- we found a low quality item for a low quality storage; just use this
            --log:debug('%s found low quality item for low quality storage: %s, %s', self._director_name, item, best_storage)
            primary_item = { item, best_storage, filter_fn }
            break
         end

         if not lq_item_for_hq then
            best_storage, filter_fn = self:_eval_item_for_restocking(item, false, temp_failed)
            if best_storage then
               lq_item_for_hq = { item, best_storage, filter_fn }
            end
         end
      end
   end

   if not primary_item then
      if hq_item_for_lq then
         --log:debug('%s found high quality item for low quality storage: %s', self._director_name, radiant.util.table_tostring(hq_item_for_lq))
         primary_item = hq_item_for_lq
         local id = hq_item_for_lq[1]:get_id()
         requeuable_items[id] = nil
         temp_failed[id] = nil
      elseif lq_item_for_hq then
         --log:debug('%s found low quality item for high quality storage: %s', self._director_name, radiant.util.table_tostring(lq_item_for_hq))
         primary_item = lq_item_for_hq
         local id = lq_item_for_hq[1]:get_id()
         requeuable_items[id] = nil
         temp_failed[id] = nil
      end
   end

   log:debug('%s marking %s items as failed', self._director_name, radiant.size(temp_failed))
   for id, item in pairs(temp_failed) do
      self._reconsidering_items[id] = nil
      self._failed_items[id] = item
      requeuable_items[id] = nil
   end

   log:debug('%s marking %s items as requeuable', self._director_name, radiant.size(requeuable_items))
   for id, item in pairs(requeuable_items) do
      local rating = self:_rate_item(item)
      if self._item_quality_cache[id] then
         self._reconsider_high_quality_items_queue:push(rating, item)
      else
         self._reconsider_items_queue:push(rating, item)
      end
      self._reconsidering_items[id] = item
   end

   if primary_item then
      return unpack(primary_item)
   end
end

function RestockDirector:_eval_item_for_restocking(item, is_primary, temp_failed)
   if item:is_valid() then
      local item_id = item:get_id()

      if not self._failed_items[item_id] and not self._reconsidering_items[item_id] and not self._covered_items[item_id] and
            stonehearth.ai:fast_call_filter_fn(self._is_restockable_predicate, item) then
         -- Select the best storage for this item.
         local item_quality = self._item_quality_cache[item_id]
         local best_storage, best_storage_score, filter_fn
         for _, storage_entry in pairs(self._storages_by_filter) do
            if stonehearth.ai:fast_call_filter_fn(storage_entry.filter_fn, item) then
               -- first check the storages that prioritize the quality of item this item is
               local storages
               if (item_quality and is_primary) or (not item_quality and not is_primary) then
                  storages = storage_entry.high_quality_storages
               else
                  storages = storage_entry.storages
               end

               for _, storage in pairs(storages) do
                  local storage_component = storage:get('stonehearth:storage')
                  if storage_component and storage_component:can_reserve_space() then
                     -- ACE: also check to make sure the item isn't currently stored in an input bin of equal or greater priority
                     if self:_is_storage_higher_priority_for_item(item, storage_component) then
                        if self:_are_reachable(item, storage) then
                           local storage_score = self:_rate_storage_for_item(storage, storage_component, item, item_quality)
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
            return best_storage, filter_fn
         else
            temp_failed[item_id] = item
         end
      end
   end
end

-- ACE: various prioritization changes
function RestockDirector:_generate_next_errand()
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

   --log:debug('%s generating next errand', self._director_name)

   -- Select a valid item.
   local target_item, best_storage, filter_fn = self:_get_next_restockable_item()
   if not target_item then
      -- After a delay, requeue failed items.
      if next(self._failed_items) then
         self:_request_process_failed_items()
      end
      return
   end

   -- Find nearby items that we can opportunistically include.
   local search_src_entity
   if get_world_location(target_item) then
      search_src_entity = target_item
   else
      search_src_entity = self._inventory:container_for(target_item)
   end

   local best_storage_component = best_storage:get('stonehearth:storage')
   local storage_priority = best_storage_component:get_input_bin_priority()
   local best_filter_fn = function(item)
      if self:_is_higher_priority_for_item(item, search_src_entity, storage_priority) then
         return filter_fn(item)
      else
         return false
      end
   end

   local prioritize_high_quality = best_storage_component:get_prioritize_restocking_high_quality()
   local rating_fn = function(item)
      local item_quality = get_item_quality(item)
      if prioritize_high_quality then
         return item_quality - 1
      elseif item_quality == stonehearth.constants.item_quality.NORMAL then
         return 1
      else
         return 0
      end
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
               -- trim down the extra items to only those that are still valid and not already covered by another errand
               for i, extra_item in ipairs(extra_items) do
                  if extra_item and extra_item:is_valid() then
                     if self._covered_items[extra_item:get_id()] then
                        extra_items[i] = nil
                     end
                  else
                     extra_items[i] = nil
                  end
               end

               storage_space_lease = best_storage_component:reserve_space(nil, 'restock errand', 1 + radiant.size(extra_items))
               if storage_space_lease then
                  -- Create the errand.
                  self._errands[errand_id] = {
                     id = errand_id,
                     filter_fn = filter_fn,
                     filter_key = self._storage_filters[best_storage:get_id()],
                     main_item = target_item,
                     item_location = item_location,
                     extra_items = extra_items,
                     storage = best_storage,
                     storage_space_lease = storage_space_lease,
                  }

                  for _, extra_item in ipairs(extra_items) do
                     self._covered_items[extra_item:get_id()] = errand_id
                  end

                  self._errands[errand_id].score = self:_rate_errand(self._errands[errand_id])
                  self._current_errand_id = (self._current_errand_id + 1) % 999999  -- avoid the (unlikely) float mantissa limit.

                  radiant.events.trigger_async(self, 'stonehearth:restock:errand_available', errand_id)
               end
            end
         else
            storage_space_lease:destroy()
            log:debug('Item/storage %s or destination storage %s not in world, marking %s as failed', search_src_entity, best_storage, target_item)
            self._failed_items[target_item_id] = target_item
         end

         self._active_nearby_item_search = nil
         self:_mark_ready_to_generate_new_errands()
      end, rating_fn)
end

-- if the item is currently in a storage, either it doesn't match the filter or this is the input_bin restock director
-- do a quick check on whether it's properly stored to see if input bin priority checks are needed
function RestockDirector:_is_storage_higher_priority_for_item(item, new_storage_comp)
   local current_storage = self._inventory:container_for(item)
   local current_storage_comp = current_storage and current_storage:get_component('stonehearth:storage')
   -- not in storage, or not supposed to be in this storage
   if not current_storage or not current_storage_comp:get_passed_items()[item:get_id()] then
      return true
   end

   if current_storage_comp:get_type() == 'input_crate' then
      if new_storage_comp:get_type() ~= 'input_crate' then
         -- in an input crate, and destination isn't an input crate
         return false
      end
   else
      if new_storage_comp:get_type() == 'input_crate' then
         -- not in an input crate, and destination is an input crate
         return true
      elseif new_storage_comp:get_type() == 'crate' and
            (current_storage_comp:get_type() == 'output_crate' or current_storage_comp:get_type() == 'stockpile') then
         -- in an output crate or stockpile, and destination is a crate
         return true
      end
   end

   return new_storage_comp:get_input_bin_priority() > current_storage:get_component('stonehearth:storage'):get_input_bin_priority()
end

function RestockDirector:_is_higher_priority_for_item(item, search_storage, priority)
   local current_storage = self._inventory:container_for(item)
   -- if the item we're looking at isn't already in storage or is in the same storage as the primary item we're restocking
   -- then we can go ahead and include it as a possible extra item
   -- otherwise, we need to check if the storage we're looking at is higher priority than the current storage
   -- if the current storage has minimum priority, it can't be higher, so we can skip that check
   -- also ignore if the current storage is set to ignore restocking
   if not current_storage or current_storage == search_storage then
      return true
   elseif priority == stonehearth.constants.inventory.input_bins.MIN_PRIORITY then
      return false
   end

   local current_storage_comp = current_storage:get_component('stonehearth:storage')
   if current_storage_comp:get_ignore_restock() then
      return false
   end

   return priority > current_storage_comp:get_input_bin_priority()
end

function RestockDirector:_on_errand_failed(errand_id)
   local errand = self._errands[errand_id]
   assert(errand)

   self._errands[errand_id] = nil
   self._errand_last_validated[errand_id] = nil

   self:_destroy_should_restock_status_trackers(errand)

   errand.storage_space_lease:destroy()

   -- Mark items no longer covered.
   if exists(errand.main_item) then
      local main_item_id = errand.main_item:get_id()
      self._covered_items[main_item_id] = nil
      -- Mark the main item as failed. Nearby items could still be valid.
      self._failed_items[main_item_id] = errand.main_item
   end
   for _, item in ipairs(errand.extra_items) do
      if exists(item) then
         local item_id = item:get_id()
         self._covered_items[item_id] = nil
         self:_on_item_added(item)
      end
   end

   radiant.events.trigger_async(self, 'stonehearth:restock:errand_canceled', errand_id)

   self:_mark_ready_to_generate_new_errands()
end

function RestockDirector:_is_errand_valid(errand_id, errand)
   local errand_last_validated = rawget(self, '_errand_last_validated')
   local timestamp = rawget(errand_last_validated, errand_id)
   local now = gamestate_now()
   if timestamp and now - timestamp <= ERRAND_VALIDITY_CACHE_EXPIRY_SEC then
      return true
   end

   local main_item = rawget(errand, 'main_item')
   local storage = rawget(errand, 'storage')
   local ai_service = rawget(stonehearth, 'ai')
   local fast_call_filter_fn = ai_service.fast_call_filter_fn
   local result = fast_call_filter_fn(ai_service, self._is_restockable_predicate, main_item)
      and self:_are_reachable(main_item, storage)
      and self._storage_filters[storage:get_id()] == rawget(errand, 'filter_key')
      and fast_call_filter_fn(ai_service, rawget(errand, 'filter_fn'), main_item)
   if result then
      rawset(errand_last_validated, errand_id, now)
   end
   return result
end

function RestockDirector:_rate_errand_for_entity_location(errand, entity_location)
   local item = rawget(errand, 'main_item')
   local distance_sq = entity_location:distance_to_squared(errand.item_location)
   local distance_to_entity_score = (1 - math_min(1, distance_sq / MAX_DISTANCE_FOR_RATING_SQ))
   return 0.5 * self:_rate_item(item, true)
        + 0.25 * rawget(errand, 'score')
        + 0.25 * distance_to_entity_score
end

function RestockDirector:_rate_errand(errand)
   local distance_sq = get_world_location(errand.storage):distance_to_squared(errand.item_location)
   local distance_to_storage_score = (1 - math_min(1, distance_sq / MAX_DISTANCE_FOR_RATING_SQ))
   local item_count_score = #errand.extra_items / (1 + MAX_EXTRA_ITEMS)
   return 0.4 * distance_to_storage_score
        + 0.6 * item_count_score
end

-- ACE: rate item higher if it's higher quality
function RestockDirector:_rate_item(item, include_tracking_rating, is_first_time)
   local item_id = item:get_id()

   local cache = rawget(self, '_item_rating_cache')
   local existing_rating = rawget(cache, item_id)
   if existing_rating and rawget(self, '_item_rating_cache_enabled') then
      return existing_rating
   end

   -- if no overall cache rating was available, re-rate it by combining conditional ratings
   -- if caches haven't been initialized yet, initialize their values for this item
   local is_undeploy_request
   local item_quality
   local entity_forms_component

   if is_first_time then
      entity_forms_component = item:get_component('stonehearth:entity_forms')
      is_undeploy_request = entity_forms_component and entity_forms_component:get_should_restock() or nil
      rawset(rawget(self, '_item_should_restock_cache'), item_id, is_undeploy_request)

      -- only cache item qualities that are higher than normal
      item_quality = get_item_quality(item)
      if item_quality > rawget(self, '_normal_item_quality') then
         rawset(rawget(self, '_item_quality_cache'), item_id, item_quality)
      else
         item_quality = nil
      end
   else
      is_undeploy_request = rawget(rawget(self, '_item_should_restock_cache'), item_id)
      item_quality = rawget(rawget(self, '_item_quality_cache'), item_id)
   end

   -- Calculate the final score.
   local score = 0
   if is_undeploy_request then
      --Undeploying should be higher priority, so return it as a totally "ideal" item.
      score = 1.0
   else
      --For any other item, check its status and accrue
      -- Loot is more important than regular restock.
      -- ACE: rate higher quality items higher

      score = 0
      local is_loot = item:get_player_id() ~= rawget(self, '_player_id')
      if is_loot then
         score = 0.5
      elseif item_quality then
         score = item_quality * 0.1
      end

      if include_tracking_rating then
         -- Prefer items we have too few of, and avoid those we have too many of.
         local tracking_data = self._restocked_item_tracker:get_tracking_data()
         local item_uri
         entity_forms_component = entity_forms_component or item:get_component('stonehearth:entity_forms')
         if entity_forms_component then
            item_uri = item:get_uri()
         else
            local iconic_form_component = item:get_component('stonehearth:iconic_form')
            if iconic_form_component then
               item_uri = iconic_form_component:get_root_entity():get_uri()
            else
               item_uri = item:get_uri()
            end
         end
         local existing_count = tracking_data:contains(item_uri) and rawget(tracking_data:get(item_uri), 'count') or 0

         if existing_count <= MAX_COUNT_FOR_NOVEL_ITEMS then
            score = score + 0.5
         elseif existing_count < MIN_COUNT_FOR_PLENTIFUL_ITEMS then
            score = score + 0.25
         end
      end
   end

   rawset(cache, item_id, score)
   return score
end

-- ACE: if storage is a regular input bin, rate it higher for higher quality items
-- if storage is for fuel consumption or quest items, rate it higher for normal quality items and lower for higher quality items
-- item_quality is either a higher than normal quality or nil
function RestockDirector:_rate_storage_for_item(storage, storage_component, item, item_quality)
   local prioritize_high_quality = storage_component:get_prioritize_restocking_high_quality()
   local quality_rating
   if prioritize_high_quality then
      quality_rating = item_quality or 0
   else
      quality_rating = not item_quality and 1 or 0
   end

   local src_location = get_world_location(item)
   if not src_location then
      local container = self._inventory:container_for(item)
      if not container then
         return quality_rating
      end
      src_location = get_world_location(container)
      if not src_location then
         return quality_rating
      end
   end
   local storage_location = get_world_location(storage)
   if storage_location then
      -- we want to scale the distance down so that quality rating has a bigger impact
      local distance_rating = math.min(MAX_DISTANCE_FOR_RATING_SQ, src_location:distance_to_squared(storage_location)) / MAX_DISTANCE_FOR_RATING_SQ
      return quality_rating - distance_rating
   else
      return -1
   end
end

function RestockDirector:_filter_to_key(filter)
   if filter then
      if filter.is_exact_filter then
         return self._player_id .. '/filter:exact:' .. filter.uri
      else
         local filter_key = self._player_id .. '/filter:'
         table.sort(filter)
         for _, material in ipairs(filter) do
            filter_key = filter_key .. '+' .. material
         end
         return filter_key
      end
   else
      return  self._player_id .. '/nofilter'
   end
end

function RestockDirector:_get_max_errands()
   local town = stonehearth.town:get_town(self._player_id)
   local task_group = town:get_task_group('stonehearth:task_groups:restock')
   local workers = task_group:get_workers()
   local disabled_workers = task_group:get_disabled_workers()
   return math.max(MIN_CONCURRENT_ERRAND_LIMIT, radiant.size(workers) - radiant.size(disabled_workers))
end

function RestockDirector:_filter_to_filter_fn(filter)
   -- Note that this assumes that the item has already been verified to be restockable.

   -- capture the current value of the filter in the closure so the
   -- implementation won't change when someone changes our filter.
   local filter_materials_lookup, filter_uri
   if filter then
      if filter.is_exact_filter then
         filter_uri = filter.uri
      else
         filter_materials_lookup = {}
         for _, material in ipairs(filter) do
            local m = Material(material)
            filter_materials_lookup[m:get_id()] = true
         end
      end
   end
   local material_test_results_cache = {}

   -- WARNING: The function we create here is a hotspot.
   -- We capture as many things as possible in upvalues for performance reasons.
   local catalog_service = stonehearth.catalog
   local catalog_data = catalog_service._catalog
   local get_material_object = catalog_service.get_material_object

   -- now create the filter function.  again, this function must work for
   -- *ALL* containers with the same filter key, which is why this is
   -- implemented in terms of global functions, parameters to the filter
   -- function, and captured local variables.
   return function(entity)
      local entity_uri = entity:get_uri()
      local catalog_data = rawget(catalog_data, entity_uri)
      if not catalog_data then
         return false
      end

      local materials = rawget(catalog_data, 'materials')
      if not materials then
         return false
      end

      if filter_materials_lookup then
         local result = rawget(material_test_results_cache, materials)
         if result == nil then
            local material_object = get_material_object(catalog_service, materials)

            -- Material testing can be expensive, especially if the filter has many materials
            -- inside it.  So, consult the filter lookup!
            -- Note that we explicltly break the abstraction here instead of using a getter.
            -- Right now, this function is _hot_ so try to be as quick as possible.
            result = false
            local material_subsets_list = rawget(material_object, 'material_subsets_list')
            for i = 1, #material_subsets_list do  -- Avoid ipairs() call overhead
               local material = rawget(material_subsets_list, i)
               if rawget(filter_materials_lookup, material) then
                  result = true
                  break
               end
            end
            rawset(material_test_results_cache, materials, result)
         end
         return result
      elseif filter_uri then
         return filter_uri == entity_uri
      else
         -- no filter means anything
         return true
      end
   end
end

-- ACE: also check interaction proxy for reachability, if it exists
function RestockDirector:_are_reachable(item, storage_or_executor)
   local is_valid = item.is_valid  -- Avoid doing the lookup twice.
   if not (is_valid(item) and is_valid(storage_or_executor)) then
      return false
   end

   local location = item:get('mob'):get_world_location()
   if not location then
      item = self._inventory:container_for(item)
      if not item or not item:is_valid() then
         return false
      end
   end

   local entity_forms = item:get('stonehearth:entity_forms')
   if entity_forms then
      item = entity_forms:get_interaction_proxy() or item
   end

   local connected = are_connected(item, storage_or_executor)
   if connected then
      return true
   end

   -- Items hanging from walls aren't topology-reachable, but can usually still be accessed, so try them.
   return location and not is_supported(location)
end

function RestockDirector:_make_is_restockable_predicate(allow_stored)
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
         if sc then
            local sc_type = sc:get_type()
            if sc_type ~= 'output_crate' then  -- We can always take things from output crates.
               if not sc:is_public() then
                  return false  -- Don't touch my private property.
               end
               if sc:get_passed_items()[entity:get_id()] then
                  if not allow_stored then
                     return false  -- Already in a storage that accepts it.
                  elseif sc_type == 'input_crate' and sc:is_input_bin_highest_priority() then
                     return false  -- ACE: We don't restock from *highest priority* input crates even if we allow stored.
                  end
               end
            end
         else
            return false
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
         if not sc:is_undeployable() then
            return false
         end
      end

      return true
   end

   return _filter_passes
end

function RestockDirector:test_only_disable_rating_cache()
   self._item_rating_cache_enabled = false
end

function RestockDirector:set_item_quality(item_id, item_quality)
   if self._item_quality_cache[item_id] ~= item_quality then
      self._item_quality_cache[item_id] = item_quality
      self._item_rating_cache[item_id] = nil
   end
end

function RestockDirector:set_should_restock(item_id, should_restock)
   if self._item_should_restock_cache[item_id] ~= should_restock then
      self._item_should_restock_cache[item_id] = should_restock
      self._item_rating_cache[item_id] = nil
   end
end

return RestockDirector
