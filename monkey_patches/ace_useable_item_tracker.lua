--[[
   changed to not track items in consumer containers or quest storage
]]
local constants = require 'stonehearth.constants'
local QUEST_STORAGE_URI = constants.game_master.quests.QUEST_STORAGE_URI

local AceUsableItemTracker = class()

function AceUsableItemTracker:create_key_for_entity(entity, storage)
   assert(entity:is_valid(), 'entity is not valid.')
   local uri = entity:get_uri()

   if not stonehearth.catalog:is_item(uri) then
      return nil
   end

   local in_public_storage
   local on_ground = self:_is_item_on_ground(entity)

   if storage and storage:get_uri() ~= QUEST_STORAGE_URI then
      local storage_component = storage:get_component('stonehearth:storage')
      -- if this item is in a fuel consumer, assume it's unavailable
      if storage_component and storage_component:is_public() and not storage:get_component('stonehearth_ace:consumer') then
         in_public_storage = true
      end
   end

   if in_public_storage or on_ground then
      return uri
   end

   return nil
end

return AceUsableItemTracker
