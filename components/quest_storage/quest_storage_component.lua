--[[
   designed primarily for caching items for delivery_quest_encounter and returning_trader_script
   manages overlapping child entities with the same destination/adjacency region as this entity
      - separate child entity generated for each uri/material
      - child entities are input storages with higher than normal priority
      - sets storage capacity for each based on how many of the uri/material requested
   allow enabling/disabling storage
      - when disabled, storage entity destination regions are cleared out so they can't be accessed
]]

local Region3 = _radiant.csg.Region3

local QuestStorageComponent = class()

local log = radiant.log.create_logger('quest_storage')

function QuestStorageComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._child_uri = self._json.child_uri or 'stonehearth_ace:containers:quest:child'
   self._sv.storages = {}
   self._storage_listeners = {}
   self._sv.capacity_multiplier = 1
end

function QuestStorageComponent:create()
   self._is_create = true

   local basic_tracker = radiant.create_controller('stonehearth:basic_inventory_tracker')
   self._sv.item_tracker = radiant.create_controller('stonehearth:inventory_tracker', basic_tracker)
end

function QuestStorageComponent:restore()
   -- we need to change this to be remotable to the client
   if self._sv._storages then
      self._sv.storages = self._sv._storages
      self._sv._storages = nil
   end

   local basic_tracker = radiant.create_controller('stonehearth:basic_inventory_tracker')
   self._sv.item_tracker = radiant.create_controller('stonehearth:inventory_tracker', basic_tracker)
   for _, storage in ipairs(self._sv.storages) do
      local storage_component = storage.entity:is_valid() and storage.entity:get_component('stonehearth:storage')
      if storage_component then
         for id, item in pairs(storage_component:get_items()) do
            self._sv.item_tracker:add_item(item, storage.entity)
         end
      end
   end
end

function QuestStorageComponent:post_activate()
   -- if a gm node is no longer valid on reload, the quest storage could already be destroyed by this point
   if self.__destroyed then
      return
   end

   self:_create_enabled_changed_listener()

   if not self._is_create then
      self:_create_storage_listeners()
   end
end

function QuestStorageComponent:destroy()
   self:_destroy_enabled_changed_listener()
   self:_destroy_storage_listeners()
   self:_destroy_all_storages(false)
end

function QuestStorageComponent:_destroy_enabled_changed_listener()
   if self._enabled_changed_listener then
      self._enabled_changed_listener:destroy()
      self._enabled_changed_listener = nil
   end
end

function QuestStorageComponent:_destroy_storage_listeners()
   for _, listeners in pairs(self._storage_listeners) do
      for _, listener in ipairs(listeners) do
         listener:destroy()
      end
   end
   self._storage_listeners = {}
end

function QuestStorageComponent:get_item_tracker()
   return self._sv.item_tracker
end

function QuestStorageComponent:get_requirements_status()
   local requirements = {}
   for _, storage in ipairs(self._sv.storages) do
      table.insert(requirements, {
         requirement = radiant.shallow_copy(storage.requirement),
         quantity = storage.quantity,
         satisfied = storage.satisfied,
      })
   end
   return requirements
end

function QuestStorageComponent:get_storage_entities()
   local storages = {}
   for _, storage in ipairs(self._sv.storages) do
      storages[storage.entity:get_id()] = storage.entity
   end
   return storages
end

-- requirement is either a uri or a material
function QuestStorageComponent:get_storage_by_requirement(requirement)
   for _, storage in ipairs(self._sv.storages) do
      if requirement == storage.requirement.uri or requirement == storage.requirement.material then
         return storage.entity:get_component('stonehearth:storage')
      end
   end
end

function QuestStorageComponent:get_storage_components()
   local storages = {}
   for _, storage in ipairs(self._sv.storages) do
      table.insert(storages, storage.entity:get_component('stonehearth:storage'))
   end
   return storages
end

function QuestStorageComponent:set_bulletin(bulletin)
   self._sv.bulletin = bulletin
   if bulletin then
      for _, storage in ipairs(self._sv.storages) do
         self:_evaluate_requirements_satisfied(storage)
      end
   end
   self.__saved_variables:mark_changed()
end

function QuestStorageComponent:set_enabled(enabled)
   self._entity:add_component('stonehearth_ace:toggle_enabled'):set_enabled(enabled)
end

function QuestStorageComponent:set_capacity_multiplier(multiplier)
   if multiplier ~= self._sv.capacity_multiplier then
      self._sv.capacity_multiplier = math.min(1, math.floor(multiplier))
      for _, storage in ipairs(self._sv.storages) do
         storage.entity:add_component('stonehearth:storage'):set_capacity(storage.requirement.quantity * multiplier)
      end

      self.__saved_variables:mark_changed()
   end
end

function QuestStorageComponent:dump_items()
   local location = radiant.entities.get_world_grid_location(self._entity)
   for _, storage in ipairs(self._sv.storages) do
      storage.entity:add_component('stonehearth:storage'):drop_all(location)
   end
end

-- optionally consume what exists in each storage, returning the amount consumed for each requirement
function QuestStorageComponent:destroy_storage(consume_contents)
   log:debug('%s destroy_storage(consume = %s)', self._entity, tostring(consume_contents))
   local consumed = {}
   if consume_contents then
      for _, storage in ipairs(self._sv.storages) do
         table.insert(consumed, {
            requirement = storage.requirement,
            num_consumed = storage.entity:get_component('stonehearth:storage'):get_num_items(),
         })
      end
   end

   local location = radiant.entities.get_world_grid_location(self._entity)
   -- remove from the world so that items can be dumped where it was
   radiant.terrain.remove_entity(self._entity)

   self:_destroy_all_storages(consume_contents, location)
   radiant.entities.destroy_entity(self._entity)
   return consumed
end

-- requirements is an array of filters for individual child storage entities
function QuestStorageComponent:set_requirements(requirements)
   -- first remove any no-longer-valid requirements
   local removed = false
   local location = radiant.entities.get_world_grid_location(self._entity)
   for i = #self._sv.storages, 1, -1 do
      local storage = self._sv.storages[i]
      local found = false
      for _, requirement in ipairs(requirements) do
         if (storage.requirement.uri and storage.requirement.uri == requirement.uri) or
               (storage.requirement.material and storage.requirement.material == requirement.material) then
            found = true
            break
         end
      end
      if not found then
         removed = true
         -- the storage tracing events will get destroyed, so manually remove all items from the tracker first
         for id, item in pairs(storage.entity:add_component('stonehearth:storage'):get_items()) do
            self._sv.item_tracker:remove_item(id)
         end
         self:_destroy_storage(table.remove(self._sv.storages, i), false, location)
      end
   end

   if removed then
      for i, storage in ipairs(self._sv.storages) do
         storage.id = i
      end
   end

   for i, requirement in ipairs(requirements) do
      self:_add_requirement(requirement)
   end
   self.__saved_variables:mark_changed()

   self:_create_storage_listeners()
   self:_update_storage_destinations(self._entity:add_component('stonehearth_ace:toggle_enabled'):get_enabled())
   return true
end

function QuestStorageComponent:add_requirement(requirement)
   if self:_add_requirement(requirement) then
      self.__saved_variables:mark_changed()
      self:_create_storage_listeners()
      self:_update_storage_destinations(self._entity:add_component('stonehearth_ace:toggle_enabled'):get_enabled())
   end
end

function QuestStorageComponent:_add_requirement(requirement)
   -- verify that we don't already have this material requirement
   -- if we do, check if we need to update the storage capacity
   for i, storage in ipairs(self._sv.storages) do
      if (storage.requirement.uri and storage.requirement.uri == requirement.uri) or
            (storage.requirement.material and storage.requirement.material == requirement.material) then
         if storage.requirement.quantity ~= requirement.quantity then
            storage.requirement.quantity = requirement.quantity
            storage.entity:add_component('stonehearth:storage'):set_capacity(requirement.quantity * self._sv.capacity_multiplier)
         end
         return
      end
   end

   local mob = self._entity:add_component('mob')
   local storage = radiant.entities.create_entity(self._child_uri, {owner = self._entity})
   storage:add_component('mob'):set_region_origin(mob:get_region_origin())
   storage:add_component('mob'):set_align_to_grid_flags(mob:get_align_to_grid_flags())

   local storage_component = storage:add_component('stonehearth:storage')
   storage_component:set_capacity(requirement.quantity * self._sv.capacity_multiplier)
   if requirement.uri then
      -- want the iconic form, if available
      local uri = requirement.uri
      local data = radiant.entities.get_component_data(uri, 'stonehearth:entity_forms')
      if data then
         uri = data.iconic_form or uri
      end
      storage_component:set_exact_filter(uri)
   elseif requirement.material then
      storage_component:set_filter({requirement.material})
   else
      log:error('%s has invalid requirement filter: %s', self._entity, radiant.util.table_tostring(requirement))
   end

   table.insert(self._sv.storages, {
      id = #self._sv.storages + 1,
      entity = storage,
      requirement = radiant.shallow_copy(requirement),
      quantity = 0,
      satisfied = false,
   })
   radiant.entities.add_child(self._entity, storage, nil, true)
   return true
end

function QuestStorageComponent:_create_enabled_changed_listener()
   self._enabled_changed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:enabled_changed', function(enabled)
         self:_update_storage_destinations(enabled)
      end)
end

function QuestStorageComponent:_create_storage_listeners()
   for _, storage in ipairs(self._sv.storages) do
      local id = storage.entity:get_id()
      if not self._storage_listeners[id] then
         local listeners = {}
         table.insert(listeners, radiant.events.listen(storage.entity, 'stonehearth:storage:item_added', function(args)
               self:_update_item_tracker(storage.entity, args.item, nil)
               self:_evaluate_requirements_satisfied(storage)
               self.__saved_variables:mark_changed()
               radiant.events.trigger(self._entity, 'stonehearth_ace:quest_storage:item_added', storage)
            end))
         table.insert(listeners, radiant.events.listen(storage.entity, 'stonehearth:storage:item_removed', function(args)
               self:_update_item_tracker(storage.entity, nil, args.item_id)
               self:_evaluate_requirements_satisfied(storage)
               self.__saved_variables:mark_changed()
            end))
         
         self._storage_listeners[id] = listeners
      end
   end
end

function QuestStorageComponent:_update_item_tracker(storage_entity, added_item, removed_item_id)
   if added_item then
      self._sv.item_tracker:add_item(added_item, storage_entity)
   elseif removed_item_id then
      self._sv.item_tracker:remove_item(removed_item_id)
   end
end

function QuestStorageComponent:_evaluate_requirements_satisfied(changed)
   changed.quantity = changed.entity:add_component('stonehearth:storage'):get_num_items()
   changed.satisfied = changed.quantity >= changed.requirement.quantity
   if self._sv.bulletin then
      local copied = radiant.shallow_copy(changed)
      copied.entity = nil
      copied.items_cached_class = copied.satisfied and 'fullyCached' or 'notFullyCached'
      self._sv.bulletin:add_i18n_data('req_' .. changed.id, copied)
   end

   local all_satisfied = true
   for _, storage in ipairs(self._sv.storages) do
      all_satisfied = all_satisfied and storage.satisfied
   end

   if all_satisfied then
      radiant.events.trigger(self._entity, 'stonehearth_ace:quest_storage:all_requirements_satisfied')
   end
end

function QuestStorageComponent:_update_storage_destinations(enabled)
   -- if the quest storage is disabled, remove all the child storage entities' destination regions
   -- if it's enabled, restore them
   for _, storage in ipairs(self._sv.storages) do
      local entity_modification = storage.entity:add_component('stonehearth_ace:entity_modification')
      if enabled then
         entity_modification:set_region3('destination', self._entity:add_component('destination'):get_region())
      else
         entity_modification:set_region3('destination', Region3())
      end
   end
end

function QuestStorageComponent:_destroy_all_storages(consume_contents, location)
   if location then
      local proxy_entity = radiant.entities.create_entity('stonehearth:object:transient')
      radiant.terrain.place_entity(proxy_entity, location)

      local effect = radiant.effects.run_effect(proxy_entity, 'stonehearth:effects:gib_effect')

      effect:set_finished_cb(
         function ()
            radiant.entities.destroy_entity(proxy_entity)
         end
      )
   end

   for _, storage in ipairs(self._sv.storages) do
      self:_destroy_storage(storage, consume_contents, location)
   end
   self._sv.storages = {}
   self.__saved_variables:mark_changed()
end

function QuestStorageComponent:_destroy_storage(storage, consume_contents, location)
   local entity = storage.entity
   if entity and entity:is_valid() then
      -- remove the storage listeners for this storage first
      local listeners = self._storage_listeners[entity:get_id()]
      if listeners then
         for _, listener in ipairs(listeners) do
            listener:destroy()
         end
         self._storage_listeners[entity:get_id()] = nil
      end

      radiant.entities.remove_child(self._entity, entity)
      if not consume_contents then
         entity:add_component('stonehearth:storage'):drop_all(location)
      end
      radiant.entities.destroy_entity(entity)
   end
end

return QuestStorageComponent
