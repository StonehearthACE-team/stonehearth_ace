-- patching this only to automatically add our own item trackers
local Material = require 'stonehearth.components.material.material'
local Inventory = require 'stonehearth.services.server.inventory.inventory'
local RestockDirector = require 'stonehearth.services.server.inventory.restock_director'
local constants = require 'stonehearth.constants'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local GOLD_URI = 'stonehearth:loot:gold'

local AceInventory = class()
local log = radiant.log.create_logger('inventory')

AceInventory._ace_old__pre_activate = Inventory._pre_activate
function AceInventory:_pre_activate()
   self:_ace_old__pre_activate()

   self:_add_more_trackers()
end

AceInventory._ace_old_activate = Inventory.activate
function AceInventory:activate()
   self:_ace_old_activate()

   self._is_initialized = true
   radiant.events.trigger(self, 'stonehearth:inventory:initialized')
end

function AceInventory:is_initialized()
   return self._is_initialized
end

-- changed stack updates to only trigger an update for wealth category items (otherwise score isn't changing)
function AceInventory:_install_listeners()
   self._storage_added_listener = radiant.events.listen(self, 'stonehearth:inventory:storage_added', self, self._on_storage_gen_changed)
   self._filter_changed_listener = radiant.events.listen(self, 'stonehearth:inventory:filter_changed', self, self._on_storage_gen_changed)
   self._destroy_listener = radiant.events.listen(radiant, 'radiant:entity:pre_destroy', self, self._on_destroy)

   self._stacks_changed_listener = radiant.events.listen(radiant, 'radiant:item:stacks_changed', function(e)
         self:_update_score_for_item(e.entity, true)
      end)
end

-- ACE: added other edibles categories
function AceInventory:_update_score_for_item(item, stacks_changed)
   if item and item:is_valid() then
      -- if this is an icon, find the root entity
      local ic = item:get_component('stonehearth:iconic_form')
      if ic then
         item = ic:get_root_entity()
         if not item or not item:is_valid() then
            return
         end
      end

      local category = radiant.entities.get_category(item)
      -- if it's a stacks change and it's not wealth (e.g., food/drink/etc.), no update necessary
      if stacks_changed and category ~= 'wealth' then
         return
      end

      -- if it's raw resources, don't score it
      if category == 'resources' or category == 'resources_animal' or category == 'resources_mineral' or category == 'resources_fiber' then
         return
      end

      -- compute the score
      local score = self:_get_score_for_item(item, category)
      local id = item:get_id()

      -- add to 'edibles' and 'net_worth' categories
      -- ACE: add 'food_prepared' but don't count 'food_animal'
      if category == 'food' or category == 'food_prepared' then
         -- if this is an edible item, add it to edibles
         stonehearth.score:change_score(item, 'edibles', 'food_inventory', score)
      else
         -- if not edible item, add to net_worth
         stonehearth.score:change_score(item, 'net_worth', 'inventory', score)
      end
   end
end

--- Given an entity, get the score for it, aka the entity's net worth
--  If we don't have a score for that entity, use the default score, which is 1
-- ACE: also pass in category since we already queried that
function AceInventory:_get_score_for_item(item, category)
   local net_worth = radiant.entities.get_net_worth(item)
   if net_worth then
      -- The value of wealth is item_score * stacks
      if category == 'wealth' then
         local stacks_component = item:get_component('stonehearth:stacks')
         local stacks = stacks_component and stacks_component:get_stacks() or 1
         return net_worth * stacks
      end
      --if not wealth, then just return value in gold
      return net_worth
   end

   -- otherwise, return 1
   return 1
end

function AceInventory:_add_more_trackers()
   -- load up a json file to see what other trackers need to be added
   local trackers = radiant.resources.load_json('stonehearth_ace:data:inventory_trackers')

   for tracker, load in pairs(trackers) do
      if load then
         self:add_item_tracker(tracker)
      end
   end
end

-- override to also pass in the inventory object to the tracker controllers
-- so they can easily check the container of an item being added
function AceInventory:add_item_tracker(controller_name)
   local tracker = self._trackers[controller_name]
   if not tracker then
      --log:debug('creating "%s" tracking controller for %s', controller_name, self._sv.player_id)
      local controller = radiant.create_controller(controller_name, self)
      assert(controller)

      local container_for = self._container_for
      tracker = radiant.create_controller('stonehearth:inventory_tracker', controller)
      for id, item in pairs(self._sv._items) do
         tracker:add_item(item, container_for[id])
      end
      self._trackers[controller_name] = tracker
      self.__saved_variables:mark_changed()
   end
   return tracker
end

-- ACE: if add_item is called with nil storage for an item already in inventory, ignore it
-- Call to tell the inventory that we're adding an item. Can be called even if the item is already in
-- the inventory for storage changes.
-- storage, check_full, and update_trackers are optional parameters
function Inventory:add_item(item, storage, check_full, update_trackers)
   local in_world_item = entity_forms_lib.get_in_world_form(item)
   if in_world_item then
      item = in_world_item
   end

   if not radiant.entities.exists(item) then
      return false
   end

   local id = item:get_id()

   -- If the item already exists in the inventory, then just update its info
   if self._sv._items[id] then
      -- ACE: this can get called if the item was immediately added to a storage, and then is added to the inventory generally
      -- we don't want to clear out its storage reference; when removing an item from storage, update_item_container is
      -- called directly instead of calling add_item with a nil storage
      if storage then
         self:update_item_container(id, storage, update_trackers)
         radiant.events.trigger(self, 'stonehearth:inventory:item_updated', { item = item })
      end
      return
   end

   if check_full and self:is_full() then
      return false
   end

   self:_add_item_internal(item, storage)
   return true
end

-- ACE: patched to add ignore_restock storage property
function AceInventory:_create_restock_directors()
   local RESTOCK_DIRECTOR_INTERVAL = '30m'
   local RESTOCK_DIRECTOR_MAX_IDLE_TIME = stonehearth.calendar:parse_duration('3h')

   local make_restock_director = function(type, allow_stored, predicate)
      local director = RestockDirector(self, allow_stored, predicate)
      self._restock_directors[type] = director

      -- Desperate times require desperate measure. For unclear reasons sometimes after a while the restock director gets stuck.
      -- So if it does, we reboot the whole thing.
      -- No, I'm not proud of this.
      self._restock_director_watchdogs[type] = stonehearth.calendar:set_interval('restock director watchdog', RESTOCK_DIRECTOR_INTERVAL, function()
            if director:has_items_in_queue() and stonehearth.calendar:get_elapsed_time() - director:get_last_success_time() > RESTOCK_DIRECTOR_MAX_IDLE_TIME then
               -- Hasn't suceessfully restocked in a while despite having items in the queue. Reboot the whole darn thing.
               log:error('Restock director stuck. Rebooting it...')
               director:destroy()
               director = RestockDirector(self, allow_stored, predicate)
               self._restock_directors[type] = director
            end
         end)
   end

   make_restock_director(constants.inventory.restock_director.types.RESTOCK, false, function(storage)
         if storage and not storage:get_ignore_restock() and storage:is_public() then
            local type = storage:get_type()
            return type ~= 'output_crate' and type ~= 'input_crate'
         end
         return false
      end)
   make_restock_director(constants.inventory.restock_director.types.INPUT_BIN, true, function(storage)
         return storage and not storage:get_ignore_restock() and storage:is_public() and storage:get_type() == 'input_crate'
      end)
end

-- TODO: Kill this once we're sure about the restock director.
local function get_filter_fn(filter, filter_key, player_id)
   -- capture the current value of the filter in the closure so the
   -- implementation won't change when someone changes our filter.
   local filter_materials_lookup, filter_uri, filter_materials_uris
   if filter then
      if filter.is_exact_filter then
         filter_uri = filter.uri
      else
         filter_materials_lookup = {}
         for _, material in ipairs(filter) do
            local m = Material(material)
            filter_materials_lookup[m:get_id()] = true
         end

         filter_materials_uris = {}
      end
   end

   -- WARNING: The function we create here is a hotspot.
   -- We capture as many things as possible in upvalues for performance reasons.
   local get_player_id = radiant.entities.get_player_id
   local catalog = stonehearth.catalog
   local get_catalog_data = catalog.get_catalog_data
   local get_material_object = catalog.get_material_object

   -- now create the filter function.  again, this function must work for
   -- *ALL* containers with the same filter key, which is why this is
   -- implemented in terms of global functions, parameters to the filter
   -- function, and captured local variables.
   local function _filter_passes(entity)
      if not entity or not entity:is_valid() then
         --log:spam('%s is not a valid entity.  cannot be stored.', tostring(entity))
         return false
      end

      -- Too expensive to call, even if we the logging level is low: log:detail('calling filter function on %s (key:%s)', entity, filter_key)

      local item_player_id = get_player_id(entity)
      if item_player_id ~= player_id then
         local task_tracker_component = entity:get_component('stonehearth:task_tracker')
         local loot_item_requested = false
         if task_tracker_component and task_tracker_component:is_task_requested(player_id, nil, 'stonehearth:loot_item') then
            loot_item_requested = true
         end

         if not loot_item_requested then
            log:detail('item player id "%s" ~= container id "%s".  returning from filter function', item_player_id, player_id)
            return false
         end
      end

      local efc = entity:get_component('stonehearth:entity_forms')
      if efc then
         if not efc:get_should_restock() then
            return false
         end
         local iconic_entity = efc:get_iconic_entity()
         return _filter_passes(iconic_entity)
      end

      if entity:get_component('stonehearth:ghost_form') then
         --log:spam('%s is a ghost form and cannot be stored.', entity)
         return false
      end

      local entity_uri = entity:get_uri()
      local catalog_data = get_catalog_data(catalog, entity_uri)
      if not catalog_data then
         --log:spam('%s does not exist in the catalog. it cannot be stored.', entity)
         return false
      end

      if not rawget(catalog_data, 'is_item') then
         --log:spam('%s is not an item.  cannot be stored.', entity)
         return false
      end

      local materials = rawget(catalog_data, 'materials')
      if not materials then
         --log:spam('%s has no material.  cannot be stored.', entity)
         return false
      end

      if entity:get_component('stonehearth:construction_progress') then
         --log:spam('%s is a construction blueprint.  cannot be stored.', entity)
         return false
      end

      -- no filter means anything
      if not filter_materials_lookup then
         if filter_uri then
            return filter_uri == entity_uri
         else
            --log:spam('container has no filter.  %s item can be stored!', entity)
            return true
         end
      end

      local material_object = get_material_object(catalog, materials)

      -- cache material testing by uri
      local cached_result = rawget(filter_materials_uris, entity_uri)
      if cached_result == nil then
         cached_result = false
         -- Material testing can be expensive, especially if the filter has many materials
         -- inside it.  So, consult the filter lookup!
         -- Note that we explicltly break the abstraction here instead of using a getter.
         -- Right now, this function is _hot_ so try to be as quick as possible.
         local material_subsets_list = rawget(material_object, 'material_subsets_list')
         for i = 1, #material_subsets_list do  -- Avoid ipairs() call overhead
            local material = rawget(material_subsets_list, i)
            if rawget(filter_materials_lookup, material) then
               --log:spam('%s matches filter and can be stored!', material)
               cached_result = true
               break
            end
         end
         rawset(filter_materials_uris, entity_uri, cached_result)
      end
      return cached_result

      -- must match at least one material in the filter, or this cannot be stored

      -- Too expensive to call, even if we the logging level is low: log:spam('%s failed filter.  cannot be stored.', entity)
      --return false
   end
   return _filter_passes
end

--AceInventory._ace_old_set_storage_filter = Inventory.set_storage_filter
function AceInventory:set_storage_filter(storage_entity, filter)
   local storage = storage_entity:get_component('stonehearth:storage')
   if not filter then
      filter = storage:get_limited_all_filter()
   end

   local player_id = self._sv.player_id
   local storage = storage_entity:get_component('stonehearth:storage')
   local is_input_crate = storage:get_type() == 'input_crate'
   local filter_key = self:filter_to_key(filter)

   filter_key = filter_key .. '(' .. player_id .. ')'
   if is_input_crate then
      filter_key = filter_key .. '; input'
   end

   -- all containers with the same filter must use the same filter function
   -- to determine whether or not an item can be stored.  this function is
   -- uniquely identified by the filter key.  this allows us to use a
   -- shared 'stonehearth:pathfinder' bfs pathfinder to find items which should
   -- go in containers rather than creating 1 bfs pathfinder per-container
   -- per worker (!!)
   local filter_fn = self._filter_key_to_filter_fn[filter_key]
   if not filter_fn then
      local town = stonehearth.town:get_town(player_id)
      if town then
         filter_fn = stonehearth.ai:filter_from_key('stonehearth:town_inventory_filter', filter_key, get_filter_fn(filter, filter_key, player_id))
         self._filter_key_to_filter_fn[filter_key] = filter_fn
      end
   end
   self._storage_to_filter_fn[storage_entity:get_id()] = filter_fn
   stonehearth.ai:reconsider_entity(storage_entity, 'storage filter changed')
   radiant.events.trigger_async(self, 'stonehearth:inventory:storage_filter_changed', { storage = storage_entity })
   return filter_fn
end

-- optionally specify either the uri or the material of the item to find in storage
function AceInventory:get_amount_in_storage(uri, material)
   local tracking_data = self:get_item_tracker('stonehearth:usable_item_tracker')
                                       :get_tracking_data()
   local count = 0

   if uri then
      local item = uri
      local entity_forms = radiant.entities.get_component_data(uri, 'stonehearth:entity_forms')
      if entity_forms and entity_forms.iconic_form then
         item = entity_forms.iconic_form
      end

      if tracking_data:contains(item) then
         count = tracking_data:get(item).count
      end
   elseif material then
      for _, item in tracking_data:each() do
         if radiant.entities.is_material(item.first_item, material) then
            count = count + item.count
         end
      end
   end

   return count
end

-- if storage is specified and combine_only, the number of remaining stacks that were unable to be added is returned (nil if none)
-- otherwise, if any gold items were created, those are returned in a table (nil if none)
function AceInventory:add_gold(amount, storage, combine_only)
   local gold_items = self:get_items_of_type(GOLD_URI)
   local stacks_to_add = amount

   -- First try to add stacks to existing gold items
   if gold_items ~= nil then
      for id, item in pairs(gold_items.items) do
         -- only consider a gold item that's not currently in use
         if not stonehearth.ai:get_ai_lease_owner(item) and (not storage or radiant.entities.get_parent(item) == storage) then
            -- get stacks for the item
            local stacks_component = item:get_component('stonehearth:stacks')
            local item_stacks = stacks_component:get_stacks()

            -- nuke some stacks
            local new_stacks = item_stacks + stacks_to_add
            local max_stacks = stacks_component:get_max_stacks()
            if new_stacks <= max_stacks then
               -- this item can hold the stacks we need. Add to stacks and we're done
               stacks_component:set_stacks(item_stacks + stacks_to_add)
               stacks_to_add = 0
            else
               local subtracted_stacks = max_stacks - item_stacks
               stacks_component:set_stacks(max_stacks)
               stacks_to_add = stacks_to_add - subtracted_stacks
            end

            radiant.events.trigger(self, 'stonehearth:inventory:item_updated', { item = item })

            if stacks_to_add <= 0 then
               break
            end
         end
      end
   end

   if stacks_to_add > 0 then
      if combine_only then
         return stacks_to_add
      end

      local items_added = {}
      -- If we got here, then we need to add gold to the town
      -- if a storage entity was specified, use that instead of default storage
      local storage_comp = storage and storage:get_component('stonehearth:storage')
      local town = stonehearth.town:get_town(self._sv.player_id)
      local default_storage = town:get_default_storage()
      local location = town:get_landing_location()
      radiant.assert(storage_comp or location, "Unable to add %s gold because the town doesn't have a location to put the gold!", stacks_to_add)

      local gold_entities_added = false
      while stacks_to_add > 0 do
         local gold = radiant.entities.create_entity(GOLD_URI, { owner = self._sv.player_id })
         local stacks_component = gold:get_component('stonehearth:stacks')
         local stacks = stacks_to_add
         if stacks > stacks_component:get_max_stacks() then
            stacks = stacks_component:get_max_stacks()
         end
         gold:get_component('stonehearth:stacks')
                  :set_stacks(stacks)
         local gold_id = gold:get_id()

         if storage_comp then
            storage_comp:add_item(gold)
         else
            local options = {
               inputs = default_storage,
               spill_fail_items = true,
               require_matching_filter_override = true,
            }
            radiant.entities.output_spawned_items({[gold_id] = gold}, location, 1, 3, options)
         end
         
         -- if it gets put in default storage, it doesn't need to be added
         if not self._container_for[gold_id] then
            self:_add_item_internal(gold)
         end
         stacks_to_add = stacks_to_add - stacks
         gold_entities_added = true
         items_added[gold_id] = gold
      end

      return items_added
   else
      -- if we didn't need to add gold items, just update the inventory tracker so that the gold count updates.
      self:get_item_tracker('stonehearth:basic_inventory_tracker')
            :mark_changed()
      self:get_item_tracker('stonehearth:usable_item_tracker')
            :mark_changed()
   end
end

function AceInventory:subtract_gold(amount, from_entity)
   local stacks_to_remove = amount
   local only_stacks_dirty = true

   if from_entity then
      local items
      local from_storage = from_entity:get_component('stonehearth:storage')
      if from_storage then
         local gold = from_storage:get_items_of_type(GOLD_URI)
         items = gold and gold.items
      else
         items = {[from_entity:get_id()] = from_entity}
      end

      if items then
         stacks_to_remove, only_stacks_dirty = self:_subtract_gold_from(stacks_to_remove, items)
      end
   end

   local gold_items = self:get_items_of_type(GOLD_URI)
   if gold_items ~= nil then
      local still_dirty = true
      if stacks_to_remove > 0 then
         stacks_to_remove, still_dirty = self:_subtract_gold_from(stacks_to_remove, gold_items.items)
      end
      -- it is annoying that we have to do this, but the inventory tracker
      -- doesn't trace the stacks of all the items.  sigh.
      if only_stacks_dirty and still_dirty then
         self:get_item_tracker('stonehearth:basic_inventory_tracker')
                  :mark_changed()
         self:get_item_tracker('stonehearth:usable_item_tracker')
                  :mark_changed()
      end
   end
end

function AceInventory:_subtract_gold_from(stacks_to_remove, items)
   local only_stacks_dirty = true
   for id, item in pairs(items) do
      if item:is_valid() then
         -- get stacks for the item
         local stacks_component = item:add_component('stonehearth:stacks')
         local item_stacks = stacks_component:get_stacks()

         -- nuke some stacks
         if item_stacks > stacks_to_remove then
            -- this item has more stacks than we need to remove, reduce the stacks and we're done
            stacks_component:set_stacks(item_stacks - stacks_to_remove)
            stacks_to_remove = 0
            radiant.events.trigger(self, 'stonehearth:inventory:item_updated', { item = item })
         else
            -- consume the whole item and run through the loop again
            radiant.entities.destroy_entity(item)
            stacks_to_remove = stacks_to_remove - item_stacks
            only_stacks_dirty = false
         end

         assert(stacks_to_remove >= 0)

         if stacks_to_remove == 0 then
            break
         end
      end
   end

   return stacks_to_remove, only_stacks_dirty
end

return AceInventory