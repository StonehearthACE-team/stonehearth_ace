local HasRaidableFarmsCheckScript = class()

function HasRaidableFarmsCheckScript:start(ctx, data)
   --Check if there are farms that are growing things. If there are no farms, don't do this
   local town = stonehearth.town:get_town(ctx.player_id)
   local farms = town:get_farms()
   for _, farm in pairs(farms) do
      local field_component = farm:get_component('stonehearth:farmer_field')
      if field_component and field_component:has_crops() then
         return true
      end
   end
   return false
end

return HasRaidableFarmsCheckScript
