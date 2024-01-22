local AutoCraftWorkshopPowered = {}

function AutoCraftWorkshopPowered.set_power_percentage(workshop, percentage)
   -- if the workshop is unpowered, or the percentage is lower than the min consumes percent, set it to 0
   -- otherwise, power percentage will scale it between 100-300%
   local workshop_comp = workshop:get_component('stonehearth:workshop')
   local mechanical_comp = workshop:get_component('stonehearth_ace:mechanical')
   if workshop_comp and mechanical_comp then
      local scaled = 0
      if percentage > 0 and percentage >= mechanical_comp:get_min_power_consumed_percent() then
         scaled = 2 * (1 - percentage) + 1
      end
      workshop_comp:set_crafting_time_modifier(scaled)
   end
end

return AutoCraftWorkshopPowered
