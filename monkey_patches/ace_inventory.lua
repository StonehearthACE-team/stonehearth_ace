-- patching this only to automatically add our own item trackers
local Material = require 'stonehearth.components.material.material'
local Inventory = require 'stonehearth.services.server.inventory.inventory'
local AceInventory = class()

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

return AceInventory