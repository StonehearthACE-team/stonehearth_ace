local EquipDuring = class()

function EquipDuring:on_buff_added(entity, buff)
   local script_info = buff:get_json().script_info
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if not script_info.equipment_replacements or not equipment_comp then
      return
   end

   self._cache_key = script_info.equipment_cache_key or 'default'

   for equipped, replacement in pairs(script_info.equipment_replacements) do
      local slot = equipment_comp:cache_equipment(self._cache_key, equipped, replacement)
   end
end

function EquipDuring:on_buff_removed(entity, buff)
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if self._cache_key and equipment_comp then
      equipment_comp:unequip_cached(self._cache_key)
   end
end

return EquipDuring
