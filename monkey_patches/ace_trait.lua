local AceTrait = class()

function AceTrait:_init_i18n_data()
   self:add_i18n_data('entity_display_name', radiant.entities.get_display_name(self._sv._entity))
   self:add_i18n_data('entity_custom_name', radiant.entities.get_custom_name(self._sv._entity))
   self:add_i18n_data('entity_custom_data', radiant.entities.get_custom_data(self._sv._entity))
end

function AceTrait:get_icon()
   return self._sv.icon
end

return AceTrait
