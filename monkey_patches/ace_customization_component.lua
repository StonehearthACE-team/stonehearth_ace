local AceCustomizationComponent = class()

local CUSTOMIZATION = {
   NONE = '[none]',
   MATERIAL_MAP = 'material_map',
   MODEL= 'model',
   ROOT = 'root',
   PACKAGES = 'packages',
   DEFAULT_VARIANT = 'default'
}

function AceCustomizationComponent:activate()
   if not self._sv._customization_cache then
      self._sv._customization_cache = {}
   end
end

function AceCustomizationComponent:change_customization(subcategory, style, cache_existing)
   assert(subcategory)
   style = style or CUSTOMIZATION.NONE
   local existing = self:get_added_styles(subcategory)

   -- remove existing style under this subcategory if one exists and save it for later use if desired (ACE)
   if existing then
      if cache_existing and not self._sv._customization_cache[existing.subcategory] then
         self._sv._customization_cache[existing.subcategory] = {
            style = existing.style,
            file_path = existing.file_path,
            variant_type = existing.variant_type
         }
         self.__saved_variables:mark_changed()
      end
      self:_remove_style(existing.subcategory, existing.style, existing.file_path, existing.variant_type)
   end

   -- replace with the new style
   self:_add_style(subcategory, style)
end

function AceCustomizationComponent:restore_cached_customization(subcategory)
   assert(subcategory)
   if not self._sv._customization_cache or not self._sv._customization_cache[subcategory] then
      return
   end

   local existing = self:get_added_styles(subcategory)
   if existing then
      self:_remove_style(existing.subcategory, existing.style, existing.file_path, existing.variant_type)
   end

   self:_add_style(subcategory, self._sv._customization_cache[subcategory].style)
   self._sv._customization_cache[subcategory] = nil
   self.__saved_variables:mark_changed()
end

return AceCustomizationComponent