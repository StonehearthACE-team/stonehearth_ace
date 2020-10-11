local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local AceInventoryTracker = class()

-- If the tracking data for this uri contains item quality info,
-- update the item quality for this entity's tracking data entry
function AceInventoryTracker:_on_item_quality_added(e)
   -- this event is triggered async, so it's possible the entity was immediately destroyed
   if not e.entity:is_valid() then
      return
   end

   local tracking_data = self._sv.tracking_data
   local key = e.uri
   if key and tracking_data:contains(key) then
      local data = tracking_data:get(key)
      if data.item_qualities then
         local entity = e.entity
         local entity_id = e.entity:get_id()

         -- If this entity isn't in the id map, it might be because it is the
         -- iconic that is being tracked, so use that if that is the case
         if not data.items[entity_id] then
            local _, iconic = entity_forms.get_forms(entity)
            if iconic and data.items[iconic:get_id()] then
               entity = iconic
               entity_id = iconic:get_id()
            else
               -- This entity/iconic are not being tracked so return 
               return
            end
         end

         for item_quality_key, entry in pairs(data.item_qualities) do
            -- Update the item quality for this entry with the updated item quality
            if entry.items[entity_id] then
               if entry.item_quality ~= e.item_quality then
                  data = self.update_item_quality_entry(entity, data, self._sv.controller)
                  self._sv.tracking_data:add(key, data)
                  self.__saved_variables:mark_changed()
                  break -- Paul: just added this line to resolve a potential Lua error for single
               end
            end
         end
      end
   end
end

return AceInventoryTracker
