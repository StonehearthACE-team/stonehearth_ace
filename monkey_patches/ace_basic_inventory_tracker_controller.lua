--[[
   changed to not track both root and iconic entities for a single item during placement
]]

local AceBasicInventoryTracker = class()

function AceBasicInventoryTracker:create(inventory)
   self._inventory = inventory
end

function AceBasicInventoryTracker:create_key_for_entity(entity)
   assert(entity:is_valid(), 'entity is not valid.')
   -- we only want to track the item if it's in storage or has a parent
   -- if this is the tracker of a storage entity, we don't care about the inventory; we only care about that for the overall inventory
   if not self._inventory or self._inventory:container_for(entity) or radiant.entities.get_parent(entity) then
      return entity:get_uri()
   end
end

return AceBasicInventoryTracker
