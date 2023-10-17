local TreatScript = class()

function TreatScript:start(ctx, data)
   self._sv.resolved_out_edge = nil
   local demand = data.demand
   local inventory = stonehearth.inventory:get_inventory(ctx.player_id)
   local sellable_item_tracker = inventory:get_item_tracker('stonehearth:resource_material_tracker')
   local tracking_data = sellable_item_tracker:get_tracking_data()
   
   if (tracking_data:contains(demand.material) and tracking_data:get(demand.material).count >= demand.count) then
      local removed_successfully = inventory:try_remove_items(demand.material, demand.count, 'stonehearth:resource_material_tracker')
      assert(removed_successfully)
      
      self._sv.resolved_out_edge = data.success_out_edge
      self.__saved_variables:mark_changed()
      return
   else
      self._sv.resolved_out_edge = data.failure_out_edge
      self.__saved_variables:mark_changed()
   end
end

function TreatScript:get_out_edge()
   return self._sv.resolved_out_edge
end

return TreatScript
