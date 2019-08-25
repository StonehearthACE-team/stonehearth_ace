local EquipDuring = class()

function EquipDuring:on_buff_added(entity, buff)
   local script_info = buff:get_json().script_info
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if not (script_info.add_equipment or script_info.unequip_slots) or not equipment_comp then
      return
   end

   -- check if the requirements are met before proceeding
   if script_info.requires_all_of then
      for _, requirement in ipairs(script_info.requires_all_of) do
         if not equipment_comp:has_item_type(requirement) then
            return
         end
      end
   end
   if script_info.requires_any_of then
      local has_requirement = false
      for _, requirement in ipairs(script_info.requires_any_of) do
         if equipment_comp:has_item_type(requirement) then
            has_requirement = true
            break
         end
      end
      if not has_requirement then
         return
      end
   end

   local cache_key = script_info.equipment_cache_key or 'default'
	
   if equipment_comp:cache_equipment(cache_key, script_info.add_equipment, script_info.unequip_slots) then
      self._cache_key = cache_key
   end
end

function EquipDuring:on_buff_removed(entity, buff)
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if self._cache_key and equipment_comp then
      equipment_comp:reset_cached(self._cache_key)
   end
end

return EquipDuring
