local WorkshopPowered = {}

function WorkshopPowered.set_power_percentage(workshop, percentage)
   -- if the workshop is unpowered, it will take 200% normal time to craft
   -- otherwise, power percentage will scale it between 25-100% (1-4x normal crafting speed)
   local workshop_comp = workshop:get_component('stonehearth:workshop')
   if workshop_comp then
      local unpowered = 2
      local powered_best = 0.25
      local powered_worst = 1
      local scaling_data = radiant.entities.get_entity_data(workshop, 'stonehearth_ace:powered_workshop')
      if scaling_data then
         unpowered = scaling_data.unpowered_time_multiplier or unpowered
         powered_best = scaling_data.powered_best_time_multiplier or powered_best
         powered_worst = scaling_data.powered_worst_time_multiplier or powered_worst
      end
      local powered_range = powered_worst - powered_best
      local scaled = (percentage == 0 and unpowered) or ((1 - percentage) * powered_range + powered_best)
      workshop_comp:set_crafting_time_modifier(scaled)
   end
end

return WorkshopPowered
