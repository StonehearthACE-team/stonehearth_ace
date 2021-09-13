--[[
   manages universal storage entities, handling changes to destination regions
]]

local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local UniversalStorage = class()
local log = radiant.log.create_logger('universal_storage')

function UniversalStorage:initialize()
   self._sv.storages = {}
   self._sv.categories = {}

   self._access_nodes_by_storage = {}  -- tables by storage id contain access node tables
   self._access_nodes = {} -- access node tables by access node entity id; each table contains node entity, traces, and current world destination region
   self._queued_items = {} -- items queued up for transfer to a universal storage entity as soon as it's registered
end

function UniversalStorage:create(player_id)
   self._sv.player_id = player_id
end

function UniversalStorage:destroy()
   self:_destroy_all_node_traces()
end

function UniversalStorage:_destroy_all_node_traces()
   for _, node in pairs(self._access_nodes) do
      self:_destroy_node_traces(node)
   end
end

function UniversalStorage:_destroy_node_traces(node)
   if node.parent_trace then
      node.parent_trace:destroy()
      node.parent_trace = nil
   end
   if node.location_trace then
      node.location_trace:destroy()
      node.location_trace = nil
   end
end

function UniversalStorage:queue_items_for_transfer_on_registration(entity, items)
   self._queued_items[entity:get_id()] = items
end

-- TODO: if this entity is already registered, it needs to be removed from its current group
-- if it's the last entity in its group, its storage should be merged with its new group storage
-- (or old group simply transformed into new group if new group doesn't already exist)
function UniversalStorage:register_storage(entity, category, group_id)
   local storage = self:_add_storage(entity, category, group_id)

   -- add any queued items for transfer
   self:_transfer_queued_items(entity, storage)
end

function UniversalStorage:unregister_storage(entity)
   local entity_id = entity:get_id()
   local node = self._access_nodes[entity_id]
   if node then
      self._access_nodes[entity_id] = nil
      self:_destroy_node_traces(node)

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

function UniversalStorage:storage_contents_changed(storage, is_empty)
   local storage_id = storage:get_id()
   local access_nodes = self._access_nodes_by_storage[storage_id]
   if access_nodes then
      for id, node in pairs(access_nodes) do
         local commands_component = node.entity:get_component('stonehearth:commands')
         if commands_component then
            commands_component:set_command_enabled('stonehearth:commands:undeploy_item', is_empty)
         end
      end
   end
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

function UniversalStorage:_add_storage(entity, category, group_id)
   local category_storages = self._sv.categories[category]
   if not category_storages then
      category_storages = {}
      self._sv.categories[category] = category_storages
   end
   local storage_id = category_storages[group_id]
   local group_storage = storage_id and self._sv.storages[storage_id] and self._sv.storages[storage_id]:is_valid()
   if not group_storage then
      local storage_uri = stonehearth_ace.universal_storage:get_universal_storage_uri(category)
      log:debug('get_universal_storage_uri(%s) = %s', tostring(category), tostring(storage_uri))
      group_storage = radiant.entities.create_entity(storage_uri, {owner = self._sv.player_id})
      log:debug('created %s from registering %s', group_storage, entity)
      radiant.terrain.place_entity_at_exact_location(group_storage, Point3.zero)

      storage_id = group_storage:get_id()
      category_storages[group_id] = storage_id
      self._sv.storages[storage_id] = group_storage
      self.__saved_variables:mark_changed()

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
         parent_trace = mob:trace_parent('universal storage access node entity added or removed')
            :on_changed(function(parent_entity)
               self:_update_access_node_destination_region(access_node)
            end),
         location_trace = mob:trace_transform('universal storage access node entity moved')
            :on_changed(function()
               self:_update_access_node_destination_region(access_node)
            end)
      }
      self._access_nodes[entity_id] = access_node
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

function UniversalStorage:_transfer_queued_items(entity, storage)
   local id = entity:get_id()
   local queued = self._queued_items[id]
   if queued then
      local storage_comp = storage:get_component('stonehearth:storage')
      for _, item in pairs(queued) do
         storage_comp:add_item(item, true)
      end

      self._queued_items[id] = nil
   end
end

function UniversalStorage:_destroy_universal_storage(storage, last_entity)
   local entity = entity_forms_lib.get_in_world_form(last_entity)
   local location = radiant.entities.get_world_grid_location(entity or last_entity) or false
   local storage_comp = storage:get_component('stonehearth:storage')
   if storage_comp then
      storage_comp:drop_all(nil, location)
   end

   radiant.entities.destroy_entity(storage)
end

return UniversalStorage
