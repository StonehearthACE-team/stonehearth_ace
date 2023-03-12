--[[
   manages universal storage entities, handling changes to destination regions
]]

local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local constants = require 'stonehearth.constants'

local UniversalStorage = class()
local log = radiant.log.create_logger('universal_storage')

local _effect_sizes = {}
for _, effect_size in pairs(constants.universal_storage.effect_sizes) do
   table.insert(_effect_sizes, effect_size)
end
table.sort(_effect_sizes,
   function(a, b)
      return not b.max_collision_size or (a.max_collision_size and a.max_collision_size < b.max_collision_size)
   end
)

function UniversalStorage:initialize()
   self._sv.storages = {}
   self._sv.categories = {}
   self._sv.access_node_effect = nil

   self._access_nodes_by_storage = {}  -- tables by storage id contain access node tables
   self._access_nodes = {} -- access node tables by access node entity id; each table contains node entity, traces, and current world destination region
   self._queued_items = {} -- items queued up for transfer to a universal storage entity as soon as it's registered
   self._queued_destination_storage = {}  -- universal storage ids by queued storage id
   self._storage_destroyed_listeners = {}
end

function UniversalStorage:create(player_id)
   self._sv.player_id = player_id

   self._is_create = true
   self:_create_inventory_loaded_listener()
end

function UniversalStorage:restore()
   self:_create_inventory_loaded_listener()
end

function UniversalStorage:post_activate()
   -- if we weren't just created, check for any storages with no access nodes and expel all their items and destroy them
   if not self._is_create then
      local town = stonehearth.town:get_town(self._sv.player_id)
      local town_entity = town and (town:get_banner() or town:get_hearth())
      local location = town and town:get_landing_location()

      for id, storage in pairs(self._sv.storages) do
         local access_nodes = self._access_nodes_by_storage[id]
         -- verify that the access nodes properly just have the universal_storage component and not the storage component
         -- local has_access_node = false
         -- for _, node in pairs(access_nodes) do
         --    if node:get_component('stonehearth:storage') then

         --    end
         -- end
         if not access_nodes or not next(access_nodes) then
            self:_destroy_universal_storage(storage, town_entity, location)
         else
            self:_add_storage_destroyed_listener(storage)
         end
      end
   end

   self:_update_all_access_node_effects()
end

function UniversalStorage:destroy()
   self:_destroy_all_node_traces_and_effects()
   self:_destroy_inventory_loaded_listener()
   --self:_destroy_storage_destroyed_listeners()
end

function UniversalStorage:_create_inventory_loaded_listener()
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   if inventory then
      if inventory:is_initialized() then
         self._can_transfer_items = true
      else
         self._inventory_loaded_listener = radiant.events.listen_once(inventory, 'stonehearth:inventory:initialized', function()
               self._inventory_loaded_listener = nil
               self._can_transfer_items = true
               --log:debug('transferring all queued items... %s', radiant.util.table_tostring(self._queued_items))
               self:_transfer_all_queued_items()
            end)
      end
   else
      log:error('no inventory found for %s! unable to transfer items', self._sv.player_id)
   end
end

function UniversalStorage:_add_storage_destroyed_listener(storage)
   local id = storage:get_id()
   if not self._storage_destroyed_listeners[id] then
      self._storage_destroyed_listeners[id] = radiant.events.listen_once(storage, 'radiant:entity:pre_destroy', function()
            self._storage_destroyed_listeners[id] = nil   
            self._sv.storages[id] = nil
            for _, category in pairs(self._sv.categories) do
               for group_id, storage_id in pairs(category) do
                  if storage_id == id then
                     category[group_id] = nil
                  end
               end
            end
            self.__saved_variables:mark_changed()
         end)
   end
end

function UniversalStorage:_destroy_inventory_loaded_listener()
   if self._inventory_loaded_listener then
      self._inventory_loaded_listener:destroy()
      self._inventory_loaded_listener = nil
   end
end

function UniversalStorage:_destroy_all_node_traces_and_effects()
   for _, node in pairs(self._access_nodes) do
      self:_destroy_node_traces_and_effect(node)
   end
end

function UniversalStorage:_destroy_node_traces_and_effect(node)
   if node.parent_trace then
      node.parent_trace:destroy()
      node.parent_trace = nil
   end
   if node.location_trace then
      node.location_trace:destroy()
      node.location_trace = nil
   end
   self:_stop_access_node_effect(node)
end

function UniversalStorage:_stop_access_node_effect(node)
   if node.effect then
      node.effect:stop()
      node.effect = nil
   end
end

function UniversalStorage:queue_items_for_transfer_on_registration(entity, items)
   if not self._queued_items[entity:get_id()] then
      self._queued_items[entity:get_id()] = items
   end
end

-- TODO: if this entity is already registered, it needs to be removed from its current group
-- if it's the last entity in its group, its storage should be merged with its new group storage
-- (or old group simply transformed into new group if new group doesn't already exist)
function UniversalStorage:register_storage(entity, category, group_id)
   local storage = self:_add_storage(entity, category, group_id)
   local id = entity:get_id()

   if self._can_transfer_items then
      -- add any queued items for transfer
      --log:debug('transferring queued items from %s... %s', entity, radiant.util.table_tostring(self._queued_items[id] or {}))
      self:_transfer_queued_items(self._queued_items[id], storage)
      self._queued_items[id] = nil
   else
      self._queued_destination_storage[id] = storage
   end
   return storage
end

function UniversalStorage:unregister_storage(entity)
   local entity_id = entity:get_id()
   local node = self._access_nodes[entity_id]
   if node then
      self._access_nodes[entity_id] = nil
      self:_destroy_node_traces_and_effect(node)

      local storage_id = node.storage_id
      local access_nodes_by_storage = self._access_nodes_by_storage[storage_id]
      if access_nodes_by_storage then
         access_nodes_by_storage[entity_id] = nil
      end

      -- if this access node is being destroyed and it's the last one in its list, destroy its universal storage entity
      -- TODO: properly handle when all remaining access nodes are *in* this storage; just blow it up? disallow undeploy if any items in its universal storage?
      if not access_nodes_by_storage or not next(access_nodes_by_storage) then
         local storage = self._sv.storages[storage_id]
         if storage then
            self._sv.storages[storage_id] = nil
            self:_destroy_universal_storage(storage, entity)
         end
      end
   end
end

-- leave the call here in case we want to do something with it later
-- but for now don't worry about whether they can be undeployed
function UniversalStorage:storage_contents_changed(storage, is_empty)
   -- local storage_id = storage:get_id()
   -- local access_nodes = self._access_nodes_by_storage[storage_id]
   -- if access_nodes then
   --    for id, node in pairs(access_nodes) do
   --       local commands_component = node.entity:get_component('stonehearth:commands')
   --       if commands_component then
   --          commands_component:set_command_enabled('stonehearth:commands:undeploy_item', is_empty)
   --       end
   --    end
   -- end
end

function UniversalStorage:get_storage_from_access_node(entity)
   local access_node = self._access_nodes[entity:get_id()]
   local storage_id = access_node and access_node.storage_id
   return storage_id and self._sv.storages[storage_id]
end

function UniversalStorage:get_storage_from_category(category, group_id)
   local category_storages = self._sv.categories[category]
   if category_storages then
      local storage_id = category_storages[group_id]
      return storage_id and self._sv.storages[storage_id]
   end
end

function UniversalStorage:get_access_nodes_from_storage(entity)
   local access_nodes = self._access_nodes_by_storage[entity:get_id()]
   if access_nodes then
      local nodes = {}
      for id, node in pairs(access_nodes) do
         table.insert(nodes, {
            entity = node.entity,
            in_world = node.destination_region ~= nil,
         })
      end
      return nodes
   end
end

function UniversalStorage:get_access_node_effect()
   return self._sv.access_node_effect
end

function UniversalStorage:set_access_node_effect(effect)
   if self._sv.access_node_effect ~= effect then
      self._sv.access_node_effect = effect
      self:_update_all_access_node_effects()
   end
end

function UniversalStorage:_update_all_access_node_effects()
   for _, node in pairs(self._access_nodes) do
      self:_update_effect(node)
   end
end

function UniversalStorage:_add_storage(entity, category, group_id)
   -- if the entity being passed also has a storage component, queue up its items for transfer
   local storage_comp = entity:get_component('stonehearth:storage')
   --log:debug('adding storage for %s (%sdestroying)...', entity, storage_comp and storage_comp.__destroying and '' or 'NOT ')
   if storage_comp and not storage_comp.__destroying then
      self:queue_items_for_transfer_on_registration(entity, storage_comp:get_items())
   end
   
   local category_storages = self._sv.categories[category]
   if not category_storages then
      category_storages = {}
      self._sv.categories[category] = category_storages
   end
   local storage_id = category_storages[group_id]
   local group_storage = storage_id and self._sv.storages[storage_id]
   if not group_storage or not group_storage:is_valid() then
      local storage_uri = stonehearth_ace.universal_storage:get_universal_storage_uri(category)
      log:debug('get_universal_storage_uri(%s) = %s', tostring(category), tostring(storage_uri))
      group_storage = radiant.entities.create_entity(storage_uri, {owner = self._sv.player_id})
      log:debug('created %s from registering %s', group_storage, entity)
      radiant.terrain.place_entity_at_exact_location(group_storage, Point3.zero)

      storage_id = group_storage:get_id()
      category_storages[group_id] = storage_id
      self._sv.storages[storage_id] = group_storage
      self.__saved_variables:mark_changed()

      self:_add_storage_destroyed_listener(group_storage)

      radiant.events.trigger(stonehearth_ace.universal_storage, 'stonehearth_ace:universal_storage:entity_created', {
         entity = group_storage,
         category = category,
         group_id = group_id,
      })
   end

   local entity_id = entity:get_id()

   local access_node = self._access_nodes[entity_id]
   if not access_node then
      local mob = entity:add_component('mob')
      access_node = {
         entity = entity,
         storage_id = storage_id,
         effect_suffix = self:_get_access_node_size(entity),
         parent_trace = mob:trace_parent('universal storage access node entity added or removed')
            :on_changed(function(parent_entity)
               self:_update_access_node_destination_region(access_node)
               self:_update_effect(access_node)
            end),
         location_trace = mob:trace_transform('universal storage access node entity moved')
            :on_changed(function()
               self:_update_access_node_destination_region(access_node)
            end)
      }
      self._access_nodes[entity_id] = access_node
      self:_update_effect(access_node)
   end

   local access_nodes_by_storage = self._access_nodes_by_storage[storage_id]
   if not access_nodes_by_storage then
      access_nodes_by_storage = {}
      self._access_nodes_by_storage[storage_id] = access_nodes_by_storage
   end
   access_nodes_by_storage[entity_id] = access_node
   
   self:_update_access_node_destination_region(access_node)

   return group_storage
end

function UniversalStorage:_update_access_node_destination_region(access_node)
   local entity = access_node.entity
   local destination = entity:get_component('destination')
   if not destination then
      return
   end

   local location = radiant.entities.get_world_grid_location(entity)
   if location then
      access_node.destination_region = radiant.entities.local_to_world(destination:get_region():get(), entity)
      access_node.adjacent_region = radiant.entities.local_to_world(destination:get_adjacent():get(), entity)
   elseif not access_node.destination_region and not access_node.adjacent_region then
      -- it's nil and it was already nil, no update necessary
      return
   else
      access_node.destination_region = nil
      access_node.adjacent_region = nil
   end

   self:_update_storage_destination_region(access_node.storage_id)
end

function UniversalStorage:_update_storage_destination_region(storage_id)
   local storage = self._sv.storages[storage_id]
   if storage then
      local destination_region = Region3()
      local adjacent_region = Region3()
      local nodes = self._access_nodes_by_storage[storage_id]
      for entity_id, node in pairs(nodes) do
         if node.destination_region then
            destination_region = destination_region + node.destination_region
         end
         if node.adjacent_region then
            adjacent_region = adjacent_region + node.adjacent_region
         end
      end

      destination_region = radiant.entities.get_region_world_to_local(destination_region, storage)
      adjacent_region = radiant.entities.get_region_world_to_local(adjacent_region, storage)

      local destination_comp = storage:add_component('destination')
      if not destination_comp:get_region() then
         destination_comp:set_region(_radiant.sim.alloc_region3())
      end
      if not destination_comp:get_adjacent() then
         destination_comp:set_adjacent(_radiant.sim.alloc_region3())
      end
      destination_comp:get_region():modify(function(cursor)
         cursor:clear()
         if destination_region then
            log:debug('%s setting destination adjacent region to bounds %s', storage, destination_region:get_bounds())
            cursor:copy_region(destination_region)
         end
      end)
      destination_comp:get_adjacent():modify(function(cursor)
         cursor:clear()
         if adjacent_region then
            log:debug('%s setting destination adjacent region to bounds %s', storage, adjacent_region:get_bounds())
            cursor:copy_region(adjacent_region)
         end
      end)

      stonehearth.ai:reconsider_entity(storage, 'adjusted universal storage destination region')
   end
end

function UniversalStorage:_get_access_node_size(entity)
   local rcs = entity:get_component('region_collision_shape')
   local region = rcs and rcs:get_region()
   if region then
      local area = region:get():get_area()

      for _, effect_size in ipairs(_effect_sizes) do
         if not effect_size.max_collision_size or area < effect_size.max_collision_size then
            return effect_size.effect_suffix
         end
      end
   end
end

function UniversalStorage:_update_effect(access_node)
   self:_stop_access_node_effect(access_node)

   local location = radiant.entities.get_world_grid_location(access_node.entity)
   if location then
      local effect = self._sv.access_node_effect
      if effect and effect ~= '' and access_node.effect_suffix then
         -- make sure the effect exists (e.g., Ethereal Storage mod hasn't been disabled)
         effect = effect .. access_node.effect_suffix
         if not radiant.resources.load_json(effect, true, false) then
            return
         end
         -- run the appropriate effect based on the access node "size"
         access_node.effect = radiant.effects.run_effect(access_node.entity, effect)
      end
   end
end

function UniversalStorage:_transfer_all_queued_items()
   local destinations = {}
   for id, items in pairs(self._queued_items) do
      local destination = self:_transfer_queued_items(items, self._queued_destination_storage[id], true)
      if destination then
         destinations[destination:get_id()] = destination
      end
   end
   for id, destination in pairs(destinations) do
      desination:get_component('stonehearth:storage'):reset_storage_filter_caches()
   end
   self._queued_destination_storage = {}
   self._queued_items = {}
end

function UniversalStorage:_transfer_queued_items(queued, storage, skip_reset)
   if queued and storage then
      local storage_comp = storage:get_component('stonehearth:storage')
      --local inventory = stonehearth.inventory:get_inventory(entity:get_player_id())
      for _, item in pairs(queued) do
         --local container = inventory:container_for(item)
         storage_comp:add_item(item, true)
         --log:debug('adding queued item %s; moving from %s to %s', item, tostring(container), tostring(inventory:container_for(item)))
         if not skip_reset then
            storage_comp:reset_storage_filter_caches()
         end
      end
   end
end

function UniversalStorage:_destroy_universal_storage(storage, last_entity, location_fallback)
   local entity = last_entity and entity_forms_lib.get_in_world_form(last_entity) or last_entity
   local location = entity and radiant.entities.get_world_grid_location(entity) or location_fallback
   -- if there's no location, try to use a point from the destination region
   if not location then
      local destination = storage:get_component('destination')
      local region = destination and destination:get_region():get()
      if region and not region:empty() then
         -- we don't have to translate/rotate anywhere because universal storages are placed at (0,0,0) with 0 rotation
         location = region:get_rect(0).min
      end
   end

   local storage_comp = storage:get_component('stonehearth:storage')
   if storage_comp then
      storage_comp:drop_all(nil, location)
   end

   radiant.entities.destroy_entity(storage)
end

return UniversalStorage
