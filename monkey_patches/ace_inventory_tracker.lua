local entity_forms = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local AceInventoryTracker = class()

function AceInventoryTracker:create(controller, is_storage)
   assert(controller)
   self._sv.controller = controller
   self._sv.tracking_data = _radiant.sim.alloc_string_map()
   self._is_storage = is_storage
end

--- Call when it's time to add an item
function AceInventoryTracker:add_item(entity, storage)
   local keys = self:_create_keys_for_entity(entity, storage)
   
   -- save the key for this entity for the future, so we know how to remove the entity
   -- from our tracking tracking_data when it's destroyed.
   if #keys > 0 then
      local changed = false
      self._sv._ids_to_keys[entity:get_id()] = keys

      for _, key in ipairs(keys) do
         -- Get existing value from key and give it to the controller so it can generate the
         -- next value
         local tracking_data = nil
         if self._sv.tracking_data:contains(key) then
            tracking_data = self._sv.tracking_data:get(key)
         end
         self._sv.tracking_data:add(key, self._sv.controller:add_entity_to_tracking_data(entity, tracking_data))
         changed = true

         radiant.events.trigger(self, 'stonehearth:inventory_tracker:item_added:sync', { key = key, item = entity })
         radiant.events.trigger_async(self, 'stonehearth:inventory_tracker:item_added', { key = key })
      end

      if changed then
         self:_consider_marking_changed()
      end
   end
end

--- Call when it's time to remove an item
--
function AceInventoryTracker:remove_item(entity_id)
   local keys = self._sv._ids_to_keys[entity_id]
   if keys then
      local changed = false
      self._sv._ids_to_keys[entity_id] = nil
      
      for _, key in ipairs(keys) do
         local controller = self._sv.controller
         local tracking_data = nil
         if self._sv.tracking_data:contains(key) then
            tracking_data = self._sv.tracking_data:get(key)
         end
         local result = controller:remove_entity_from_tracking_data(entity_id, tracking_data)
         if result then
            self._sv.tracking_data:add(key, result)
         else
            self._sv.tracking_data:remove(key)
         end
         changed = true

         radiant.events.trigger(self, 'stonehearth:inventory_tracker:item_removed:sync', { key = key, item_id = entity_id })
         radiant.events.trigger_async(self, 'stonehearth:inventory_tracker:item_removed', { key = key })
      end

      if changed then
         self:_consider_marking_changed()
      end
   end
end

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
                  self:_consider_marking_changed()
                  break -- Paul: just added this line to resolve a potential Lua error for single
               end
            end
         end
      end
   end
end

function AceInventoryTracker:_consider_marking_changed()
   self._has_changed = true
   if not self._is_storage then
      self:mark_changed(true)
   end
end

function AceInventoryTracker:mark_changed(internal_call)
   if self._has_changed or not internal_call then
      self._has_changed = false
      self.__saved_variables:mark_changed()
   end
end

return AceInventoryTracker
