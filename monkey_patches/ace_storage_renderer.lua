-- Renders the current contents of a stonehearth:storage component as iconics attached
-- to the ATTITEM* bones of the entity's main model if the JSON specifies render_contents as true.
local AceStorageRenderer = class()

local REPOSITION_FILL = 'fill'
local REPOSITION_SHIFT = 'shift'

function AceStorageRenderer:_move_item_renderer(from_bone, to_bone)
   local item_id = self._bone_to_item[from_bone]
   local item = radiant.entities.get_entity(item_id)
   self._bone_to_item[from_bone] = nil
   self._item_render_entities[item_id]:destroy()
   self._item_render_entities[item_id] = nil
   self:_render_item(item, to_bone)
end

function AceStorageRenderer:_update()
   local data = self._datastore:get_data()
   local items = data.items
   local reposition_items = data.reposition_items
   
   -- Remove any items that no longer exist.
   for bone, item_id in pairs(self._bone_to_item) do
      if not items[item_id] then
         self._bone_to_item[bone] = nil
         self._item_render_entities[item_id]:destroy()
         self._item_render_entities[item_id] = nil
      end
   end

   -- if we want to shift items when some are removed, do that immediately
   if reposition_items == REPOSITION_SHIFT then
      local bones = self:_get_bones()
      for i, bone in ipairs(bones) do
         if not self._bone_to_item[bone] then
            local found_bone
            for j = i + 1, #bones do
               if self._bone_to_item[bones[j]] then
                  -- we found one; shift it to position i
                  self:_move_item_renderer(bones[j], bone)
                  found_bone = true
                  break
               end
            end
            if not found_bone then
               break
            end
         end
      end
   end

   -- Fill empty bones with any existing items.
   local bone_index = 1
   for _, bone in ipairs(self:_get_bones()) do
      if not self._bone_to_item[bone] then
         -- Could avoid the O(n^2) here, but N is in practice too low to bother.
         for item_id, item in pairs(items) do
            if not self._item_render_entities[item_id] then
               self:_render_item(item, bone)
               break
            end
         end
      end
   end

   -- if we just want to fill in early spots with items from later spots, wait until the end to do that
   if reposition_items == REPOSITION_FILL then
      local bones = self:_get_bones()
      for i, bone in ipairs(bones) do
         if not self._bone_to_item[bone] then
            local found_bone
            for j = #bones, i + 1, -1 do
               if self._bone_to_item[bones[j]] then
                  -- we found one; shift it to position i
                  self:_move_item_renderer(bones[j], bone)
                  found_bone = true
                  break
               end
            end
            if not found_bone then
               break
            end
         end
      end
   end
end

return AceStorageRenderer
