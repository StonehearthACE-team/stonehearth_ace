local AceAIComponent = class()

-- override just to add custom data
function AceAIComponent:set_status_text_key(key, data)
   self._sv.status_text_key = key
   if data and data['target'] then
      local entity = data['target']
      if type(entity) == 'string' then
         local catalog_data = stonehearth.catalog:get_catalog_data(entity)
         if catalog_data then
            data['target_display_name'] = catalog_data.display_name
            data['target_custom_name'] = ''
         end
      elseif entity and entity:is_valid() then
         data['target_display_name'] = radiant.entities.get_display_name(entity)
         data['target_custom_name']  = radiant.entities.get_custom_name(entity)
         -- add custom data
         data['target_custom_data']  = radiant.entities.get_custom_data(entity)
      end
      data['target'] = nil
   end
   self._sv.status_text_data = data
   self.__saved_variables:mark_changed()
end

return AceAIComponent
