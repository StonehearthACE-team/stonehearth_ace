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
   self._sv._storages = {}
   self._storage_listeners = {}
end

function QuestStorageComponent:create()
   self._is_create = true
end

function QuestStorageComponent:post_activate()
   -- if a gm node is no longer valid on reload, the quest storage could already be destroyed by this point
   if self.__destroyed then
      return
   end

   self:_create_enabled_changed_listener()

   if self._is_create then
      local player_id = radiant.entities.get_player_id(self._entity)
      local enabled = stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'auto_enable_quest_storage', true)
      self:set_enabled(enabled)
   else
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
   for _, listener in ipairs(self._storage_listeners) do
      listener:destroy()
   end
   self._storage_listeners = {}
end

function QuestStorageComponent:get_requirements_status()
   local requirements = {}
   for _, storage in ipairs(self._sv._storages) do
      table.insert(requirements, {
         requirement = radiant.shallow_copy(storage.requirement),
         quantity = storage.quantity,
         satisfied = storage.satisfied,
      })
   end
   return requirements
end

function QuestStorageComponent:get_storage_components()
   local storages = {}
   for _, storage in ipairs(self._sv._storages) do
      table.insert(storages, storage.entity:get_component('stonehearth:storage'))
   end
   return storages
end

function QuestStorageComponent:set_bulletin(bulletin)
   self._sv.bulletin = bulletin
   self.__saved_variables:mark_changed()
   if bulletin then
      for _, storage in ipairs(self._sv._storages) do
         self:_evaluate_requirements_satisfied(storage)
      end
   end
end

function QuestStorageComponent:set_enabled(enabled)
   self._entity:add_component('stonehearth_ace:toggle_enabled'):set_enabled(enabled)
end

function QuestStorageComponent:dump_items()
   local location = radiant.entities.get_world_grid_location(self._entity)
   for _, storage in ipairs(self._sv._storages) do
      storage.entity:add_component('stonehearth:storage'):drop_all(location)
   end
end

-- optionally consume what exists in each storage, returning the amount consumed for each requirement
function QuestStorageComponent:destroy_storage(consume_contents)
   log:debug('%s destroy_storage(consume = %s)', self._entity, tostring(consume_contents))
   local consumed = {}
   if consume_contents then
      for _, storage in ipairs(self._sv._storages) do
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
   if #self._sv._storages > 0 then
      log:error('%s cannot set_requirements because it already has storages set up', self._entity)
      return false
   end

   local mob = self._entity:add_component('mob')
   for i, requirement in ipairs(requirements) do
      local storage = radiant.entities.create_entity(self._child_uri, {owner = self._entity})
      storage:add_component('mob'):set_region_origin(mob:get_region_origin())
      storage:add_component('mob'):set_align_to_grid_flags(mob:get_align_to_grid_flags())

      local storage_component = storage:add_component('stonehearth:storage')
      storage_component:set_capacity(requirement.quantity)
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

      table.insert(self._sv._storages, {
         id = i,
         entity = storage,
         requirement = radiant.shallow_copy(requirement),
         quantity = 0,
         satisfied = false,
      })
      radiant.entities.add_child(self._entity, storage, nil, true)
   end

   self:_create_storage_listeners()
   self:_update_storage_destinations(self._entity:add_component('stonehearth_ace:toggle_enabled'):get_enabled())
   return true
end

function QuestStorageComponent:_create_enabled_changed_listener()
   self._enabled_changed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:enabled_changed', function(enabled)
         self:_update_storage_destinations(enabled)
      end)
end

function QuestStorageComponent:_create_storage_listeners()
   self:_destroy_storage_listeners()

   for _, storage in ipairs(self._sv._storages) do
      table.insert(self._storage_listeners, radiant.events.listen(storage.entity, 'stonehearth:storage:item_added', function()
            self:_evaluate_requirements_satisfied(storage)
         end))
      table.insert(self._storage_listeners, radiant.events.listen(storage.entity, 'stonehearth:storage:item_removed', function()
            self:_evaluate_requirements_satisfied(storage)
         end))
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
   for _, storage in ipairs(self._sv._storages) do
      all_satisfied = all_satisfied and storage.satisfied
   end

   if all_satisfied then
      radiant.events.trigger(self._entity, 'stonehearth_ace:quest_storage:all_requirements_satisfied')
   end
end

function QuestStorageComponent:_update_storage_destinations(enabled)
   -- if the quest storage is disabled, remove all the child storage entities' destination regions
   -- if it's enabled, restore them
   for _, storage in ipairs(self._sv._storages) do
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

   for _, storage in ipairs(self._sv._storages) do
      local entity = storage.entity
      if entity and entity:is_valid() then
         radiant.entities.remove_child(self._entity, entity)
         if not consume_contents then
            entity:add_component('stonehearth:storage'):drop_all(location)
         end
         radiant.entities.destroy_entity(entity)
      end
   end
   self._sv._storages = {}
end

return QuestStorageComponent
