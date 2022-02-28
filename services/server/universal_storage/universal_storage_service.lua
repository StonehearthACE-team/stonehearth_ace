--[[
   manages universal storage entities, handling changes to destination regions
]]

local Entity = _radiant.om.Entity
local validator = radiant.validator
local DEFAULT_CATEGORY = 'default'
local UNIVERSAL_STORAGE_URI = 'stonehearth_ace:containers:universal_storage'

local UniversalStorageService = class()
local log = radiant.log.create_logger('universal_storage_service')

function UniversalStorageService:initialize()
   self._sv = self.__saved_variables:get_data()
   if not self._sv.new_group_id then
      self._sv.new_group_id = 1
   end
   if not self._sv.player_storages then
      self._sv.player_storages = {}
   end

   self._player_traces = {}
   self._queued_items = {}

   self._storage_type_data = radiant.resources.load_json('stonehearth_ace:data:universal_storage')
end

function UniversalStorageService:destroy()
   log:debug('shutting down universal storage service')

   self:_destroy_all_player_traces()
end

function UniversalStorageService:_destroy_all_player_traces()
   for _, trace in pairs(self._player_traces) do
      trace:destroy()
   end
   self._player_traces = {}
end

function UniversalStorageService:_destroy_player_trace(entity_id)
   if self._player_traces[entity_id] then
      self._player_traces[entity_id]:destroy()
      self._player_traces[entity_id] = nil
   end
end

function UniversalStorageService:set_access_node_effect(player_id, effect)
   local universal_storage = self._sv.player_storages[player_id]
   if universal_storage then
      universal_storage:set_access_node_effect(effect)
   end
end

function UniversalStorageService:get_default_category()
   return DEFAULT_CATEGORY
end

function UniversalStorageService:get_universal_storage_uri(category)
   category = category or DEFAULT_CATEGORY
   local data = self._storage_type_data.categories[category]
   if data and data.storage_uri then
      return data.storage_uri
   else
      return self._storage_type_data.categories[DEFAULT_CATEGORY].storage_uri
   end
end

function UniversalStorageService:get_universal_storage(player_id, category, group_id)
   category = category or DEFAULT_CATEGORY
   group_id = group_id or 0

   local player_storage = self._sv.player_storages[player_id]
   if player_storage then
      return player_storage:get_storage_from_category(category, group_id)
   end
end

function UniversalStorageService:get_storage_from_access_node_command(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local player_storage = self._sv.player_storages[entity:get_player_id()]
   local storage = player_storage and player_storage:get_storage_from_access_node(entity)
   return { storage = storage }
end

function UniversalStorageService:get_new_group_id()
   return self._sv.new_group_id
end

function UniversalStorageService:queue_items_for_transfer_on_registration(entity, items)
   self._queued_items[entity:get_id()] = items
end

-- TODO: if this entity is already registered, it needs to be removed from its current group
-- if it's the last entity in its group, its storage should be merged with its new group storage
-- (or old group simply transformed into new group if new group doesn't already exist)
function UniversalStorageService:register_storage(entity)
   local us_comp = entity:get_component('stonehearth_ace:universal_storage')
   if us_comp then
      local player_id = entity:get_player_id()
      local entity_id = entity:get_id()

      if not self._player_traces[entity_id] then
         self._player_traces[entity_id] = entity:trace_player_id('universal storage service')
            :on_changed(function(new_player_id)
               if new_player_id ~= player_id then
                  player_id = new_player_id

                  self:unregister_storage(entity)
                  -- clear out the group before re-registering
                  us_comp:set_group_id(nil)
                  self:register_storage(entity)
               end
            end)
      end

      local category = us_comp:get_category() or DEFAULT_CATEGORY
      local group_id = us_comp:get_group_id() or 0
      
      local player_storage = self._sv.player_storages[player_id]
      if not player_storage then
         player_storage = radiant.create_controller('stonehearth_ace:universal_storage', player_id)
         self._sv.player_storages[player_id] = player_storage
      end

      player_storage:register_storage(entity, category, group_id)

      if group_id >= self._sv.new_group_id then
         self._sv.new_group_id = group_id + 1
      end
   end
end

function UniversalStorageService:unregister_storage(entity)
   local player_storage = self._sv.player_storages[entity:get_player_id()]
   if player_storage then
      player_storage:unregister_storage(entity)
   end
   self:_destroy_player_trace(entity:get_id())
end

function UniversalStorageService:storage_contents_changed(storage, is_empty)
   local player_storage = self._sv.player_storages[storage:get_player_id()]
   if player_storage then
      player_storage:storage_contents_changed(storage, is_empty)
   end
end

return UniversalStorageService
