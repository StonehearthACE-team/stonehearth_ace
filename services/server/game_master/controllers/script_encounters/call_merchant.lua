local CallMerchantScript = class()

function CallMerchantScript:start(ctx, data)
   local player_mercantile = stonehearth_ace.mercantile:get_player_controller(ctx.player_id)
   if player_mercantile then
      player_mercantile:spawn_merchant(data.category .. '.' .. data.merchant)
   end
end

return CallMerchantScript
