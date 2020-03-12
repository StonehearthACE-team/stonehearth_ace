local StorageComponent = require 'stonehearth.components.storage.storage_component'
AceStorageComponent = class()

AceStorageComponent._ace_old_create = StorageComponent.create
function AceStorageComponent:create()
   
   self._is_create = true
   self:_ace_old_create()

end

AceStorageComponent._ace_old_activate = StorageComponent.activate
function AceStorageComponent:activate()   
   
   self:_ace_old_activate()
   
   local json = radiant.entities.get_json(self) or {}
   if self._is_create then
      if json.default_filter then
         self:set_filter(json.default_filter)
      end
      self._sv.is_hidden = json.is_hidden or false -- public inventory that's accessible, but hidden from UI
      -- also set the filter to none if it's hidden storage
      -- if self._sv.is_hidden then
      --    self:_set_filter_to_none()
      -- end
   end

   -- communicate this setting to the renderer
   self._sv.reposition_items = json.reposition_items
   self.__saved_variables:mark_changed()
end

return AceStorageComponent