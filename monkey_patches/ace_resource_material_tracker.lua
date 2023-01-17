--[[
   changed to not track items in consumer containers or quest storage
]]

local constants = require 'stonehearth.constants'
local QUEST_STORAGE_URI = constants.game_master.quests.QUEST_STORAGE_URI

local AceResourceMaterialTracker = class()

function AceResourceMaterialTracker:create_key_for_entity(entity, storage)
   assert(entity:is_valid(), 'entity is not valid.')

   local in_reachable_storage
   local on_ground = self:_is_item_on_ground(entity)

   if storage and storage:get_uri() ~= QUEST_STORAGE_URI then
      -- If this item is in a storage that is not a crafter's ingredient storage,
      -- it should become available eventually
      local storage_component = storage:get_component('stonehearth:storage')
      if storage_component and storage_component:get_type() ~= 'crafter_backpack' and not storage:get_component('stonehearth_ace:consumer') then
         in_reachable_storage = true
      end
   end

   local keys = {}
   if in_reachable_storage or on_ground then
      for material, _ in pairs(stonehearth.constants.resources) do
         if radiant.entities.is_material(entity, material) then
            table.insert(keys, material)
         end
      end
   end

   return keys
end

return AceResourceMaterialTracker
