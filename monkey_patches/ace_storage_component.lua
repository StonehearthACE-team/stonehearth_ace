local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local StorageComponent = require 'stonehearth.components.storage.storage_component'
AceStorageComponent = class()

local GOLD_URI = 'stonehearth:loot:gold'

local log = radiant.log.create_logger('storage_component')

AceStorageComponent._ace_old_create = StorageComponent.create
function AceStorageComponent:create()
   self._is_create = true

   local basic_tracker = radiant.create_controller('stonehearth:basic_inventory_tracker')
   self._sv.item_tracker = radiant.create_controller('stonehearth:inventory_tracker', basic_tracker, true)

   local default_storage_filter_none = stonehearth.client_state:get_default_storage_filter_none(self._entity:get_player_id())
   if default_storage_filter_none == nil then
      -- Grab host config value if client state value not set
      default_storage_filter_none = radiant.util.get_config('default_storage_filter_none', false)
   end

   -- set the output-crate-specific filter list if it's an output crate and just had the default filter list
   -- do this separately up here so its starting filter can be set to none if that gameplay setting is set
   if self._type == 'output_crate' and self._sv.filter_list == 'stonehearth:ui:stockpile:filters' then
      self._sv.filter_list = 'stonehearth_ace:ui:output_box:filters'
   end

   if stonehearth_ace.universal_storage:is_universal_storage_uri(self._entity:get_uri()) then
      -- make sure the filter can accept everything
      self._sv.filter = nil
   elseif (self._sv.is_public and default_storage_filter_none) or self._sv.is_single_filter or self._type == 'input_crate' then
      self:_set_filter_to_none()
   end
end

AceStorageComponent._ace_old_restore = StorageComponent.restore
function AceStorageComponent:restore()
   if self._entity:get_component('stonehearth_ace:universal_storage') then
      -- move all entities out of this storage and queue them up to be transferred in the proper universal_storage entity
      stonehearth_ace.universal_storage:queue_items_for_transfer_on_registration(self._entity, self._sv.items)
      self._sv.items = {}
      self._sv.num_items = 0
      self:_on_contents_changed()
      self._entity:remove_component('stonehearth:storage')
      return
   end

   -- Recreate the tracking data. It isn't actually saved, as the format is not kept backward-compatible.
   local basic_tracker = radiant.create_controller('stonehearth:basic_inventory_tracker')
   self._sv.item_tracker = radiant.create_controller('stonehearth:inventory_tracker', basic_tracker, true)
   for id, item in pairs(self._sv.items) do
      self._sv.item_tracker:add_item(item, self._entity)
   end
   self._sv.item_tracker:mark_changed()
end

AceStorageComponent._ace_old_activate = StorageComponent.activate
function AceStorageComponent:activate()
   -- if it's already been destroyed, don't activate it
   if self.__destroying then
      return
   end

   -- whenever a storage filter checks for any contained entities that match a filter,
   -- cache those results and update them on individual item removals and additions
   self._storage_filter_cache = {}
   self._num_storage_filter_caches = 0
   self._location = radiant.entities.get_world_grid_location(self._entity)

   self:_ace_old_activate()
   
   local json = radiant.entities.get_json(self) or {}
   if self._is_create then
      if json.default_filter then
         self:set_filter(json.default_filter)
      end
      -- also set the filter to none if it's hidden storage
      -- if self._sv.is_hidden then
      --    self:_set_filter_to_none()
      -- end
   end

   self._allow_item_removal = json.allow_item_removal ~= false

   self._always_mark_changed = self._sv.is_public or json.render_contents
   --self:mark_changed()

   self._sv.is_hidden = json.is_hidden or false -- public inventory that's accessible, but hidden from UI
   self._sv.show_filter = json.show_filter ~= false -- whether to show the filter UI
   self._sv.allow_default = json.allow_default ~= false  -- can be set to town default storage
   if self._type == 'output_crate' then
      self._sv.allow_default = false
   end
   -- starting default can override allow_default (that way you can create default storage that can't be toggled by the user)
   if self._is_create and json.start_default then
      local town = stonehearth.town:get_town(self._entity)
      if town then
         town:add_default_storage(self._entity)
      end
   end

   if json.limit_all_filter ~= false then
      local filter = {}
      local data = radiant.resources.load_json(self._sv.filter_list, true, false)
      
      if data and data.stockpile then
         for _, group in pairs(data.stockpile) do
            if group.categories then
               for _, entry in pairs(group.categories) do
                  if entry.filter then
                     table.insert(filter, entry.filter)
                  end
               end
            end
         end
      end

      self._limited_all_filter = filter
   end

   self._ignore_restock = json.ignore_restock
   self._drop_all_on_undeploy = json.drop_all_on_undeploy

   local bounds = stonehearth.constants.inventory.input_bins
   if self._type == 'input_crate' then
      local priority_range = bounds.MAX_PRIORITY - bounds.MIN_PRIORITY
      local priority = math.min(math.max(json.priority or 1, bounds.MIN_PRIORITY), bounds.MAX_PRIORITY)
      self._is_input_bin_highest_priority = (priority == bounds.MAX_PRIORITY)
      self._input_bin_priority = (priority - bounds.MIN_PRIORITY) / (priority_range + 1)
   else
      self._input_bin_priority = bounds.MIN_PRIORITY
   end

   -- communicate this setting to the renderer
   self._sv.render_root_items = json.render_root_items
	self._sv.render_filter_model = json.render_filter_model
	self._sv.render_filter_model_threshold = json.render_filter_model_threshold or 0.5
   self._sv.reposition_items = json.reposition_items
   self.__saved_variables:mark_changed()
end

AceStorageComponent._ace_old_post_activate = StorageComponent.post_activate
function AceStorageComponent:post_activate()
   -- if it's already been destroyed, don't activate it
   if self.__destroying then
      return
   end

   self:_ace_old_post_activate()
end

AceStorageComponent._ace_old_destroy = StorageComponent.__user_destroy
function AceStorageComponent:destroy()
   self.__destroying = true

   local inventory = stonehearth.inventory:get_inventory(self._entity:get_player_id())
   if inventory then
      inventory:remove_storage(self._entity:get_id())
   end

   if self._attention_effect then
      self._attention_effect:stop()
      self._attention_effect = nil
   end

   log:debug('%s destroying...', self._entity)

   self._storage_filter_cache = {}
   self._num_storage_filter_caches = 0

   self:_ace_old_destroy()
end

function AceStorageComponent:is_undeployable()
   return self._drop_all_on_undeploy or self:is_empty()
end

--AceStorageComponent._ace_old__on_contents_changed = StorageComponent._on_contents_changed
function AceStorageComponent:_on_contents_changed()
	-- Crates cannot undeploy when they are carrying stuff.
   -- ACE: change to check whether it's undeployable rather than empty (e.g., drop_all_on_undeploy)
   local commands_component = self._entity:get_component('stonehearth:commands')
   if commands_component then
      commands_component:set_command_enabled('stonehearth:commands:undeploy_item', self:is_undeployable())
   end

   if not self:is_empty() then
      -- If we just got filled with items, but we have an existing undeploy task, drop all of our items
      -- so that our items don't become inaccessible when we get restocked.
      local efc = self._entity:get_component('stonehearth:entity_forms')
      if efc and efc:get_should_restock() then
         self:drop_all()
      end
   end

   -- Crate cancellable status may have changed now
   self:_update_cancellable()

	if not self:is_empty() and self._sv.filter and self._sv.render_filter_model then
		if (self._sv.num_items / self._sv.capacity) >= self._sv.render_filter_model_threshold then
			self._entity:get_component('render_info'):set_model_variant(tostring(self._cached_filter_key))
		else
			self._entity:get_component('render_info'):set_model_variant('')
		end
	end

   stonehearth_ace.universal_storage:storage_contents_changed(self._entity, self:is_empty())
end

function AceStorageComponent:_on_parent_changed()
   local inventory = self._inventory
   if inventory then
      local position = radiant.entities.get_world_grid_location(self._entity)
      --Whether this storage is actually avilable for placing items into it.
      --Items like undeployed crates are not available.
      if position then
         inventory:add_storage(self._entity)
         self._filter_fn = inventory:set_storage_filter(self._entity, self._sv.filter)
         self._location = position
      else
         if self._drop_all_on_undeploy then
            self:drop_all(self._location)
         end
         inventory:remove_storage(self._entity:get_id())
      end
   end

   local parent = radiant.entities.get_parent(self._entity)
   if parent and self._sv._drop_all_timer then
      -- Destroy drop all timer now if we are now placed
      self:_destroy_drop_all_timer()
   end

   self:_update_cancellable()
end

function AceStorageComponent:_get_filter_cache(filter_fn)
   local cache = self._storage_filter_cache[filter_fn]
   if not cache then
      cache = {
         passed = {},
         --failed = {},
         untested = radiant.shallow_copy(self._sv.items),
      }
      --log:debug('%s created filter storage cache for filter_fn %s with %s untested items', self._entity, filter_fn, radiant.size(self._sv.items))
      self._storage_filter_cache[filter_fn] = cache
      self._num_storage_filter_caches = self._num_storage_filter_caches + 1
   end

   return cache
end

function AceStorageComponent:reset_storage_filter_caches()
   for filter_fn, cache in pairs(self._storage_filter_cache) do
      cache.passed = {}
      cache.untested = radiant.shallow_copy(self._sv.items)
   end
end

function AceStorageComponent:reconsider_entity_in_filter_caches(item_id, item)
   log:debug('%s reconsidering item id %s as %s in filter caches...', self._entity, item_id, tostring(item))
   for filter_fn, cache in pairs(self._storage_filter_cache) do
      rawset(cache.passed, item_id, nil)
      --cache.failed[item_id] = nil
      rawset(cache.untested, item_id, item)
   end
end

function AceStorageComponent:storage_contains_filter_fn(filter_fn)
   local cache = self:_get_filter_cache(filter_fn)
   --local passed, failed, untested = cache.passed, cache.failed, cache.untested
   local passed, untested = cache.passed, cache.untested
   
   -- if we already pass, return true
   -- we have to process through in case the items have been destroyed and are no longer valid
   for id, item in pairs(passed) do
      if item:is_valid() then
         return true
      else
         rawset(passed, id, nil)
      end
   end

   -- otherwise, if we have no untested items, return false
   if not next(cache.untested) then
      return false
   end

   -- otherwise, go through all the untested items and test them now
   -- stopping early if we find a passing item
   local ai_service = stonehearth.ai
   for id, item in pairs(untested) do
      rawset(untested, id, nil)
      if ai_service:fast_call_filter_fn(filter_fn, item) then
         rawset(passed, id, item)
         --rawset(failed, id, nil)
         return true
      --else
         --rawset(passed, id, nil)
         --rawset(failed, id, true)
      end
   end

   return false
end

-- this duplicates a lot of code from the above storage_contains_filter_fn() function,
-- but this is a performance hotspot
-- the is_max_rating_fn should be used locally to record actual item ratings / best item
function AceStorageComponent:eval_best_passing_item(filter_fn, is_max_rating_fn)
   local cache = self:_get_filter_cache(filter_fn)
   --local passed, failed, untested = cache.passed, cache.failed, cache.untested
   local passed, untested = cache.passed, cache.untested

   -- first process through all passed items
   for id, item in pairs(passed) do
      if item:is_valid() then
         if is_max_rating_fn(id, item) then
            return
         end
      else
         rawset(passed, id, nil)
      end
   end

   -- if we have no untested items, return false
   if not next(untested) then
      return
   end
   
   -- if we haven't gotten a max rating item yet, test the untested
   -- stopping early if we find a max rating passing item
   local ai_service = stonehearth.ai
   for id, item in pairs(untested) do
      rawset(untested, id, nil)
      if ai_service:fast_call_filter_fn(filter_fn, item) then
         rawset(passed, id, item)
         --rawset(failed, id, nil)
         if is_max_rating_fn(id, item) then
            return true
         end
      --else
         --rawset(passed, id, nil)
         --rawset(failed, id, true)
      end
   end

   return
end

function AceStorageComponent:get_limited_all_filter()
   return self._limited_all_filter
end

function AceStorageComponent:get_filter()
   return self._sv.filter or self._limited_all_filter
end

function AceStorageComponent:get_filter_key()
   if not self._cached_filter_key then
      self._cached_filter_key = stonehearth.inventory:get_inventory(radiant.entities.get_player_id(self._entity)):filter_to_key(self._sv.filter)
   end

   return self._cached_filter_key
end

function AceStorageComponent:is_input_bin_highest_priority()
   return self._is_input_bin_highest_priority
end

function AceStorageComponent:get_input_bin_priority()
   return self._input_bin_priority
end

function AceStorageComponent:get_ignore_restock()
   return self._ignore_restock
end

function AceStorageComponent:is_hidden()
   return self._sv.is_hidden
end

function AceStorageComponent:is_single_filter()
   return self._sv.is_single_filter
end

function AceStorageComponent:allow_default()
   return self._sv.allow_default
end

function AceStorageComponent:allow_item_removal()
   -- inventory sets up its item trackers in pre-activate
   -- so either we have to override the storage component entirely and set this up in initialize
   -- or we can do a special check here
   if self._allow_item_removal == nil then
      local json = radiant.entities.get_json(self) or {}
      self._allow_item_removal = json.allow_item_removal ~= false
   end
   return self._allow_item_removal
end

function AceStorageComponent:is_output_bin_for_crafter(job_id)
   if job_id and self._type == 'output_crate' then
      if not self._sv.filter then
         return true
      end
      if not self._sv.filter.is_exact_filter then
         for _, mat in ipairs(self._sv.filter) do
            if mat == job_id then
               return true
            end
         end
      end
   end
end

-- allow for specifying a priority_location for universal_storage, and try to send to default storage instead of landing location
-- if priority_location is false (not nil), *this* entity's location will be ignored
function AceStorageComponent:drop_all(fallback_location, priority_location)
   if self:is_empty() then
      return {} -- Nothing to drop
   end

   local items = {}
   for id, item in pairs(self._sv.items) do
      if item and item:is_valid() then
         table.insert(items, item)
      end
   end

   self._storage_filter_cache = {}
   self._num_storage_filter_caches = 0

   local get_player_id = radiant.entities.get_player_id
   for _, item in ipairs(items) do
      self:remove_item(item:get_id(), nil, get_player_id(item))
   end

   local player_id = get_player_id(self._entity)
   local default_storage
   local town = stonehearth.town:get_town(player_id)
   -- if this was private storage, don't automatically put it in default (public) storage
   if town and self._sv.is_public then
      -- unregister this storage from default; if we're dropping all the items, even if it's not getting destroyed, we probably don't want more stuff in here
      -- especially the items we're trying to drop!
      town:remove_default_storage(self._entity:get_id())
      default_storage = town:get_default_storage()
   end
   local entity = entity_forms_lib.get_in_world_form(self._entity)
   local location = priority_location or
         (priority_location == nil and (radiant.entities.get_world_grid_location(entity or self._entity) or fallback_location)) or
         (town and town:get_landing_location())

   local options = {
      owner = player_id,
      inputs = default_storage,
      spill_fail_items = true,
      require_matching_filter_override = true,
   }
   radiant.entities.output_spawned_items(items, location, 1, 4, options)

   stonehearth.ai:reconsider_entity(self._entity, 'removed all items from storage')

   return items
end

function AceStorageComponent:add_gold_item(item, combine_only)
   if item:get_uri() == GOLD_URI then
      local stacks_comp = item:add_component('stonehearth:stacks')
      local stacks = stacks_comp:get_stacks()
      local result = self:add_gold(stacks, combine_only)
      if radiant.util.is_number(result) then
         stacks_comp:set_stacks(result)
      else
         radiant.entities.destroy_entity(item)
         return result
      end
   end

   return false
end

function AceStorageComponent:add_gold(amount, combine_only)
   return self._inventory:add_gold(amount, self._entity, combine_only)
end

-- overriding for __saved_variables:mark_changed() optionality
function AceStorageComponent:add_item(item, force_add, owner_player_id)
   if self:is_full() and not force_add then
      return false
   end

   local id = item:get_id()
   if self._sv.items[id] then
      return true
   end

   -- At one point in time we had (and still may have) a bug where an entity's
   -- root form could be placed in the world *AND* the iconic form was in storage.
   -- Certainly that's a bug and should be found and fixed, but if we encounter it here
   -- (e.g. in a save file or an unfortunate series of events that leads to an error()
   -- at just the right moment causing this discrepencey) just silently ignore the add
   -- request.  This has the effect of "removing" the iconic entity from the world, since
   -- the guy who asked for it to be put into storage has released the previous reference
   -- to it (e.g. taken it off the carry bone).
   local root, iconic = entity_forms_lib.get_forms(item)
   if iconic and item == iconic then
      local in_world_item = entity_forms_lib.get_in_world_form(item)
      if in_world_item == root then
         log:error('cannot add %s to storage, root form %s is currently in world!', iconic, root)
         self:remove_item(item:get_id())
         return false
      end
   elseif iconic and item == root then
      radiant.verify(false, 'cannot add %s to storage because it is the root form!', root)
      self:remove_item(item:get_id())
      return false
   end

   self._sv.items[id] = item
   self._sv.num_items = self._sv.num_items + 1
   self:_filter_item(item)
   self._sv.item_tracker:add_item(item, self._entity)

   local inventory = self._inventory

   if owner_player_id and owner_player_id ~= '' then
      inventory = stonehearth.inventory:get_inventory(owner_player_id) or self._inventory
   end

   if inventory then
      inventory:add_item(item, self._entity) -- force add to inventory
   end

   if item:is_valid() and not force_add then
      stonehearth.ai:reconsider_entity(item, 'added item to storage')
      -- Don't need to let AI know to reconsider this container because reconsider_entity already calls on the storage
   end
   self:_on_contents_changed()
   self:_consider_marking_changed()

   radiant.events.trigger_async(self._entity, 'stonehearth:storage:item_added', {
         item = item,
         item_id = item:get_id(),
      })
   if self:is_full() then
      radiant.events.trigger_async(self._entity, 'stonehearth:storage:fullness_changed', true)
   end

   return true
end

function AceStorageComponent:remove_item(id, inventory_predestroy, owner_player_id)
   assert(type(id) == 'number', 'expected entity id')

   local item = self._sv.items[id]
   if not item then
      return nil
   end

   if self:is_full() then
      radiant.events.trigger_async(self._entity, 'stonehearth:storage:fullness_changed', false)  -- Async, so when delivery, this will be true.
   end

   self._sv.num_items = self._sv.num_items - 1
   self._sv.items[id] = nil
   self._passed_items[id] = nil
   self._filtered_items[id] = nil
   self._sv.item_tracker:remove_item(id)

   if not inventory_predestroy then
      local inventory = self._inventory

      if owner_player_id and owner_player_id ~= '' then
         inventory = stonehearth.inventory:get_inventory(owner_player_id) or self._inventory
      end
      
      if inventory then
         --Item isn't part of storage anymore, so storage is now nil
         inventory:update_item_container(id, nil)
      end

      if item:is_valid() then
         stonehearth.ai:reconsider_entity(item, 'removed item from storage')
         self:reconsider_entity_in_filter_caches(id, nil)

         -- Note: We need to reconsider the storage container here because the item is no longer part of storage
         -- and therefore the ai service will not automatically reconsider the storage.
         -- But we need the storage to be reconsidered because it's possible it was full and now is not.
         stonehearth.ai:reconsider_entity(self._entity, 'removed item from storage')
      end
   end

   self:_on_contents_changed()
   self:_consider_marking_changed()

   local event_item = not inventory_predestroy and item:is_valid() and item or nil

   radiant.events.trigger_async(self._entity, 'stonehearth:storage:item_removed', {
         item_id = id,
         item = event_item,
      })
   return item
end

function AceStorageComponent:_consider_marking_changed()
   self._has_changed = true
   -- if we're rendering the contents or it's a private storage, go ahead and update immediately (it's probably small)
   if self._always_mark_changed or not stonehearth.presence:is_multiplayer() or
         stonehearth.client_state:get_client_gameplay_setting(self._player_id, 'stonehearth_ace', 'limit_network_data') == 'unlimited' then
      self:mark_changed()
   end
end

function AceStorageComponent:mark_changed()
   if self._has_changed then
      self._has_changed = false
      self.__saved_variables:mark_changed()
      self._sv.item_tracker:mark_changed(true)
   end
end

function AceStorageComponent:get_item_tracker()
   return self._sv.item_tracker
end

function AceStorageComponent:get_items_of_type(uri)
   local tracking_data = self._sv.item_tracker:get_tracking_data()
   if tracking_data:contains(uri) then
      return tracking_data:get(uri)
   end
   return nil
end

AceStorageComponent._ace_old_set_filter = StorageComponent.set_filter
function AceStorageComponent:set_filter(filter)
   self._sv._has_set_filter = true
   self:_ace_old_set_filter(filter)
end

function AceStorageComponent:_refresh_attention_effect()
   if self._sv.is_single_filter then
      local filter = self._sv.filter
      local lacks_filter = not self._sv._has_set_filter

      if lacks_filter and filter then
         if filter.is_exact_filter then
            lacks_filter = filter.uri == ''
         else
            lacks_filter = next(filter) == nil
         end
      end

      local has_effect = self._attention_effect ~= nil
      if lacks_filter ~= has_effect then
         if lacks_filter then
            self._attention_effect = radiant.effects.run_effect(self._entity, 'stonehearth:effects:attention_effect', nil, nil, { playerColor = radiant.entities.get_player_color(self._entity) })
         else
            self._attention_effect:stop()
            self._attention_effect = nil
         end
      end
   end
end

return AceStorageComponent