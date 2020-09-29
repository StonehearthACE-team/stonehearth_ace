local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'

local HealingItemTracker = class()

-- Inventory trackers shouldn't restore or initialize. They will be recreated on load.

function HealingItemTracker:create_key_for_entity(entity, storage)
	local is_healing_item = radiant.entities.is_material(entity, 'healing_item')
   if is_healing_item then
      local in_public_storage
      local on_ground = self:_is_item_on_ground(entity)

      if storage then
         local storage_component = storage:get_component('stonehearth:storage')
         if storage_component and storage_component:is_public() then
            in_public_storage = true
         end
      end

      if in_public_storage or on_ground then
         local uri = entity:get_uri()
         healing_lib.cache_healing_item(uri, entity)
         return uri
      end
   end
   
	return nil
end

function HealingItemTracker:_is_item_on_ground(entity)
   local mob = entity:add_component('mob')
   local parent = mob:get_parent()
   return parent and parent:get_id() == radiant._root_entity_id
end

function HealingItemTracker:add_entity_to_tracking_data(entity, tracking_data)
	return entity
end

function HealingItemTracker:remove_entity_from_tracking_data(entity_id, tracking_data)
	return nil
end

return HealingItemTracker
