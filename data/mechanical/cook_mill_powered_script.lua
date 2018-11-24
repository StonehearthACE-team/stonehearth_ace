local CookMillPowered = {}

function CookMillPowered.set_power_percentage(mill, percentage)
   -- if the mill is unpowered, it will take 200% normal speed
   -- otherwise, power percentage will scale it between 25-100%
   local workshop_comp = mill:get_component('stonehearth:workshop')
   if workshop_comp then
      local scaled = (percentage == 0 and 2) or ((1 - percentage) * 0.75 + 0.25)
      workshop_comp:set_crafting_time_modifier(scaled)
   end
end

return CookMillPowered