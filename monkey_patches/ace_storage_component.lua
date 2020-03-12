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
   end

   -- communicate this setting to the renderer
	self._sv.render_filter_model = json.render_filter_model
	self._sv.render_filter_model_threshold = json.render_filter_model_threshold or 0.5
   self._sv.reposition_items = json.reposition_items
   self.__saved_variables:mark_changed()
end

AceStorageComponent._ace_old__on_contents_changed = StorageComponent._on_contents_changed
function AceStorageComponent:_on_contents_changed()

	self:_ace_old__on_contents_changed()

	if not self:is_empty() and self._sv.filter and self._sv.render_filter_model then
		if (self._sv.num_items / self._sv.capacity) >= self._sv.render_filter_model_threshold then
			self._entity:get_component('render_info'):set_model_variant(tostring(self._sv._cached_filter_key))
		else
			self._entity:get_component('render_info'):set_model_variant('')
		end
	end

end

return AceStorageComponent