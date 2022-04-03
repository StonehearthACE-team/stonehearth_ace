local TownIncapacitationCheck = class()

function TownIncapacitationCheck:start(ctx, info)
   local population = stonehearth.population:get_population(ctx.player_id)
   
   for _, citizen in population:get_citizens():each() do
      local incapacitation_component = citizen:get_component('stonehearth:incapacitation')
      if incapacitation_component and not incapacitation_component:is_incapacitated() or incapacitation_component and incapacitation_component:is_rescued() then
         return false
      end
   end

   return true
end

return TownIncapacitationCheck
