local HasRaidableFarmsCheckScript = class()

function HasRaidableFarmsCheckScript:start(ctx, data)
   --Check if there are farms that are growing things. If there are no farms, don't do this
   local town = stonehearth.town:get_town(ctx.player_id)
   local farms = town:get_farms()
   for _, farm in pairs(farms) do
      local field_component = farm:get_component('stonehearth:farmer_field')
      if field_component and field_component:has_crops() then
         -- if specific farm field types are required, check if this is one of those types
         if not data.required_field_type or data.required_field_type[field_component:get_field_type()] then
            return true
         end
      end
   end
   return false
end

return HasRaidableFarmsCheckScript
