local CallMerchantScript = class()

function CallMerchantScript:start(ctx, data)
   local merchant = stonehearth_ace.mercantile:get_player_controller(ctx.player_id):_spawn_merchant(data.category .. '.' .. data.merchant)
   merchant:add_component('stonehearth_ace:merchant'):show_bulletin(true)
end

return CallMerchantScript
