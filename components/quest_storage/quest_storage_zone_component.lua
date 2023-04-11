local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local QuestStorageZoneComponent = class()

local log = radiant.log.create_logger('quest_storage_zone')

function QuestStorageZoneComponent:initialize()
   self._sv.quest_storages = {}
   -- track the index of the point used for each quest storage
   -- so the point object can be cleared out when the quest storage entity is removed
   self._sv.quest_storage_point_indexes = {}

   self._destroy_listeners = {}
end

function QuestStorageZoneComponent:activate()
   self:_load_json()
   self:_create_destroy_listeners()
end

function QuestStorageZoneComponent:post_activate()
   -- TODO: check/wait for in world status
   self:_register()
end

function QuestStorageZoneComponent:destroy()
   self:_unregister()
   self:_destroy_destroy_listeners()
end

function QuestStorageZoneComponent:get_pattern()
   return self._json.pattern
end

function QuestStorageZoneComponent:get_size_options()
   return self._json.size
end

function QuestStorageZoneComponent:apply_settings(size, rotation, points)
   self._sv.size = size
   self._sv.rotation = rotation
   local pts = {}
   for _, point in ipairs(points) do
      table.insert(pts, {
         location = radiant.util.to_point3(point)
      })
   end
   self._sv.points = pts
   self.__saved_variables:mark_changed()
end

function QuestStorageZoneComponent:add_quest_storage(storage, location)
   local id = storage:get_id()
   self._sv.quest_storages[id] = storage

   -- try to find the location in our list of points
   local local_location = location - radiant.entities.get_world_grid_location(self._entity)
   for index, point in ipairs(self._sv.points) do
      if point.location == local_location then
         self._sv.quest_storage_point_indexes[id] = index
         point.storage = storage
         break
      end
   end

   self.__saved_variables:mark_changed()

   self:_create_destroy_listener(id, storage)
end

function QuestStorageZoneComponent:_load_json()
   self._json = radiant.entities.get_json(self) or {}

   -- remote to client renderer
   self._sv.zone_color = self._json.zone_color
   local town = stonehearth.town:get_town(self._entity)
   self._sv.sample_container = town and town:get_default_quest_storage_uri() or
         stonehearth.constants.game_master.quests.DEFAULT_QUEST_STORAGE_CONTAINER_URI
   self.__saved_variables:mark_changed()
end

function QuestStorageZoneComponent:_create_destroy_listeners()
   for id, storage in pairs(self._sv.quest_storages) do
      self:_create_destroy_listener(id, storage)
   end
end

function QuestStorageZoneComponent:_create_destroy_listener(id, storage)
   local listener = radiant.events.listen(storage, 'radiant:entity:pre_destroy', function()
         listener:destroy()
         self._destroy_listeners[id] = nil
         self:_remove_quest_storage(id)
      end)

   self._destroy_listeners[id] = listener
end

function QuestStorageZoneComponent:_destroy_destroy_listeners()
   for id, listener in pairs(self._destroy_listeners) do
      listener:destroy()
   end
   self._destroy_listeners = {}
end

function QuestStorageZoneComponent:_remove_quest_storage(id)
   self._sv.quest_storages[id] = nil
   local index = self._sv.quest_storage_point_indexes[id]
   if index then
      self._sv.quest_storage_point_indexes[id] = nil
      local point = self._sv.points[index]
      if point then
         point.storage = nil
      end
   end
   self.__saved_variables:mark_changed()
end

function QuestStorageZoneComponent:_register()
   local town = stonehearth.town:get_town(self._entity:get_player_id())
   if town then
      town:register_quest_storage_zone(self._entity)
   end
end

function QuestStorageZoneComponent:_unregister()
   local town = stonehearth.town:get_town(self._entity:get_player_id())
   if town then
      town:unregister_quest_storage_zone(self._entity:get_id())
   end
end

function QuestStorageZoneComponent:get_available_locations()
   local world_location = radiant.entities.get_world_grid_location(self._entity)
   local locations = {}

   for _, point in ipairs(self._sv.points) do
      if not point.storage then
         table.insert(locations, {
            location = world_location + point.location,
            facing = -self._sv.rotation * 90,
            zone = self._entity
         })
      end
   end

   return locations
end

return QuestStorageZoneComponent
