local EquipDuring = class()

function EquipDuring:on_buff_added(entity, buff)
   local script_info = buff:get_json().script_info
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if not (script_info.equipment_replacements or script_info.equipment_additions) or not equipment_comp then
      return
   end

   local cache_key = script_info.equipment_cache_key or 'default'
   local is_cached
	
	if script_info.equipment_replacements then
		for replacement, equipped in pairs(script_info.equipment_replacements) do
			is_cached = is_cached or equipment_comp:cache_equipment(cache_key, replacement, equipped, true)
		end
	end
	
	if script_info.equipment_additions then
		for addition, equipped in ipairs(script_info.equipment_additions) do
			is_cached = is_cached or equipment_comp:cache_equipment(cache_key, addition, equipped, false)
		end
	end

   if is_cached then
      self._cache_key = cache_key
   end
end

function EquipDuring:on_buff_removed(entity, buff)
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if self._cache_key and equipment_comp then
      equipment_comp:unequip_cached(self._cache_key)
   end
end

return EquipDuring
