local ChangeCustomizations = class()

function ChangeCustomizations:on_buff_added(entity, buff)
   local script_info = buff:get_json().script_info
   for subcategory, style in pairs(script_info.customizations) do
      entity:add_component('stonehearth:customization'):change_customization(subcategory, style, true)
   end
end

function ChangeCustomizations:on_buff_removed(entity, buff)
   local script_info = buff:get_json().script_info
   for subcategory, style in pairs(script_info.customizations) do
      entity:get_component('stonehearth:customization'):restore_cached_customization(subcategory)
   end
end

return ChangeCustomizations
