local EquipDuring = class()

function EquipDuring:on_buff_added(entity, buff)
   local script_info = buff:get_json().script_info
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if not script_info.equipment_replacements or not equipment_comp then
      return
   end

   self._cache_key = script_info.equipment_cache_key or 'default'

   --[[
      specify which items can be replaced by this new equipment
      e.g., maybe tier 1-2 herbalist hat will get replaced by the bee hat, but tier 3 herbalist hat has it built in or something?
      "equipment_replacements": {
         "new_item_uri": [
            "potential_existing_uri",
            "potential_existing_uri_2",
            "potential_existing_uri_3"
         ]
      }
   ]]
   for replacement, equipped in pairs(script_info.equipment_replacements) do
      local slot = equipment_comp:cache_equipment(self._cache_key, replacement, equipped)
   end
end

function EquipDuring:on_buff_removed(entity, buff)
   local equipment_comp = entity:get_component('stonehearth:equipment')
   if self._cache_key and equipment_comp then
      equipment_comp:unequip_cached(self._cache_key)
   end
end

return EquipDuring
