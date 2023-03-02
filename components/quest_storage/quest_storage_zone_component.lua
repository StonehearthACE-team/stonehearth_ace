local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local QuestStorageZoneComponent = class()

local log = radiant.log.create_logger('quest_storage_zone')

function QuestStorageZoneComponent:initialize()
   self._sv._points = {}
end

function QuestStorageZoneComponent:post_activate()
   -- TODO: check/wait for in world status
   self:_register()
end

function QuestStorageZoneComponent:destroy()
   self:_unregister()
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
   return {}
end

return QuestStorageZoneComponent
