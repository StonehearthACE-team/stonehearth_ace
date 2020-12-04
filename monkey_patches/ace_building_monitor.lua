local AceBuildingMonitor = class()

function AceBuildingMonitor:_update_material_status()
   local building = self._entity:get('stonehearth:build2:building')
   local remaining_costs, _ = building:get_remaining_resource_cost()

   local basic_inventory_tracker = self._inventory:get_item_tracker('stonehearth:resource_material_tracker')
   local player_color = stonehearth.presence:get_color_integer(self._player_id)

   local missing_resources = false
   for mat, count in pairs(remaining_costs) do
      -- we only care about a missing resource if we don't have any of it banked already (this matches vanilla experience)
      if not building:has_banked_resource(mat) and not basic_inventory_tracker:get_tracking_data():contains(mat) then
         missing_resources = true
         break
      end
   end

   if missing_resources and not self._out_of_resources_effect then
      self._out_of_resources_effect = radiant.effects.run_effect(self._entity, 'stonehearth:effects:attention_effect', nil, nil, { playerColor = player_color })
   elseif not missing_resources and self._out_of_resources_effect then
      self._out_of_resources_effect:stop()
      self._out_of_resources_effect = nil
   end
end

return AceBuildingMonitor
