local AceAttributesComponent = class()

function AceAttributesComponent:get_unmodified_attribute(name, default)
   local attribute_data = self:_get_attribute_data(name)

   if attribute_data then
      return attribute_data.value
   end

   if default == nil then
      return self:_get_default_value(name)
   end

   return default
end

return AceAttributesComponent
