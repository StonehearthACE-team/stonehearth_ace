local rng = _radiant.math.get_default_rng()
local ChangeCustomizations = class()

function ChangeCustomizations:on_buff_added(entity, buff)
   local script_info = buff:get_json().script_info
   if script_info.customizations then
      for subcategory, style in pairs(script_info.customizations) do
         if type(style) == 'table' then
            local pick = style[rng:get_int(1, #style)]
            entity:add_component('stonehearth:customization'):change_customization(subcategory, pick, true)
         else
            entity:add_component('stonehearth:customization'):change_customization(subcategory, style, true)
         end
      end
   end
end

function ChangeCustomizations:on_buff_removed(entity, buff)
   local script_info = buff:get_json().script_info
   if script_info.customizations then
      for subcategory, style in pairs(script_info.customizations) do
         entity:get_component('stonehearth:customization'):restore_cached_customization(subcategory)
      end
   end
end

return ChangeCustomizations
