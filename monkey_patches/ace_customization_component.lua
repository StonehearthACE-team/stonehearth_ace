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
      end
      self:_remove_style(existing.subcategory, existing.style, existing.file_path, existing.variant_type)
   end

   -- replace with the new style
   self:_add_style(subcategory, style)
end

-- Build a map from category to array of style options/ ACE: added ordinal sorting
function AceCustomizationComponent:_build_customization_indices(options)
   local indices = {}
   for category, subcategories in pairs(options.categories) do
      local styles_for_category = {}
      for _, subcategory in ipairs(subcategories) do
         -- get style values for this subcategory
         local values = options.styles[subcategory] and options.styles[subcategory].values or {}

         -- convert style values map to an array
         local temp = radiant.keys(values)

         -- ACE: sort by ordinal
         table.sort(temp, function(a, b)
            -- Check if 'ordinal' exists in both tables
            if values[a].ordinal and values[b].ordinal then
               return values[a].ordinal < values[b].ordinal
            elseif values[a].ordinal then
               return true
            elseif values[b].ordinal then
               return false
            else
               return a > b
            end
         end)

         -- sort alphabetically
         -- table.sort(temp)

         local styles_array = {}
         for _, style in ipairs(temp) do
            -- insert a kv-pair which maps from subcategory to style name
            if not values[style].hidden then
               table.insert(styles_array, { [subcategory] = style })
            end
         end

         -- put the subcategory style arrays into a category array
         table.insert(styles_for_category, styles_array)
      end

      -- compute the cartesian product using each subcategory to get every combination of the subcategory styles
      -- we need to do this to compress multiple subcategories into indices
      indices[category] = radiant.util.cartesian_product(styles_for_category)
   end

   return indices
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
end

return AceCustomizationComponent