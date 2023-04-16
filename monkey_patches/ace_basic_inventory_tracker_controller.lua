--[[
   ACE: Take two on trying to fix the iconic/entity/ghost double-counting issue
]]

local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local AceBasicInventoryTracker = class()

function AceBasicInventoryTracker:create_key_for_entity(entity)
   assert(entity:is_valid(), 'entity is not valid.')

   -- check if this is a root entity that isn't in the world
   -- if so, we don't want to track it
   local root = entity_forms_lib.get_root_entity(entity)
   if root ~= entity or radiant.entities.get_world_grid_location(entity) then
      return entity:get_uri()
   end
end

return AceBasicInventoryTracker
