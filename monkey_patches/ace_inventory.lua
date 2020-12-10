-- patching this only to automatically add our own item trackers
local Material = require 'stonehearth.components.material.material'
local Inventory = require 'stonehearth.services.server.inventory.inventory'
local RestockDirector = require 'stonehearth.services.server.inventory.restock_director'
local constants = require 'stonehearth.constants'
local GOLD_URI = 'stonehearth:loot:gold'

local AceInventory = class()
local log = radiant.log.create_logger('inventory')

AceInventory._ace_old__pre_activate = Inventory._pre_activate
function AceInventory:_pre_activate()
   self:_ace_old__pre_activate()

   self:_add_more_trackers()
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
         if not storage:get_ignore_restock() and storage:is_public() then
            local type = storage:get_type()
            return type ~= 'output_crate' and type ~= 'input_crate'
         end
         return false
      end)
   make_restock_director(constants.inventory.restock_director.types.INPUT_BIN, true, function(storage)
         return not storage:get_ignore_restock() and storage:is_public() and storage:get_type() == 'input_crate'
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
            radiant.entities.output_spawned_items({[gold_id] = gold}, location, 1, 3, nil, nil, default_storage, true)
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
         items = from_storage:get_items_of_type(GOLD_URI).items
      else
         items = {[from_entity:get_id()] = from_entity}
      end

      stacks_to_remove, only_stacks_dirty = self:_subtract_gold_from(stacks_to_remove, items)
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

   return stacks_to_remove, only_stacks_dirty
end

return AceInventory