local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local FertilizerTracker = class()

--[[
   Track everything that's either a consumable or has a useful command (not place/move/remove)
]]

-- Inventory trackers shouldn't restore or initialize. They will be recreated on load.

function FertilizerTracker:create_key_for_entity(entity, storage)
	local fertilizer_data = radiant.entities.get_entity_data(entity, 'stonehearth_ace:fertilizer')
   if fertilizer_data then
      local in_public_storage
      local on_ground = self:_is_item_on_ground(entity)

      if storage then
         local storage_component = storage:get_component('stonehearth:storage')
         if storage_component and storage_component:is_public() then
            in_public_storage = true
         end
      end

      if in_public_storage or on_ground then
         return tostring(entity:get_id())
      end
   end
   
	return nil
end

function FertilizerTracker:_is_item_on_ground(entity)
   local mob = entity:add_component('mob')
   local parent = mob:get_parent()
   return parent and parent:get_id() == radiant._root_entity_id
end

function FertilizerTracker:add_entity_to_tracking_data(entity, tracking_data)
	return entity
end

function FertilizerTracker:remove_entity_from_tracking_data(entity_id, tracking_data)
	return nil
end

return FertilizerTracker
