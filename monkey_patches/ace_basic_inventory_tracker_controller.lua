--[[
   changed to not track both root and iconic entities for a single item during placement
]]
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local AceBasicInventoryTracker = class()

function AceBasicInventoryTracker:create(inventory)
   self._inventory = inventory
end

function AceBasicInventoryTracker:create_key_for_entity(entity)
   assert(entity:is_valid(), 'entity is not valid.')
   -- if this item has multiple forms, we only want to track this form if its other form isn't in storage or has a parent
   -- we don't care about whether this entity is in the world or in storage, only making sure it doesn't have another form that is
   -- if this is the tracker of a storage entity, we don't care about the inventory; we only care about that for the overall inventory
   local root, iconic = entity_forms_lib.get_forms(entity)
   if self._inventory and root and iconic then
      local other = (entity == root) and iconic or root
      if self._inventory:container_for(other) or radiant.entities.get_parent(other) then
         return
      end
   end

   return entity:get_uri()
end

return AceBasicInventoryTracker
