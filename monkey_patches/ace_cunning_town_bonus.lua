local AceCunningTownBonus = class()

function AceCunningTownBonus:apply_trader_gold_bonus(base_gold)
   return base_gold * 1
end

function AceCunningTownBonus:apply_trader_quantity_bonus(quantity)
   return quantity * 1.5
end

function AceCunningTownBonus:apply_sell_price_bonus(price)
   return price * 1.1
end

function AceCunningTownBonus:apply_road_speed_bonus(speed)
   return speed * 3
end

--new ACE bonus
function AceCunningTownBonus:get_reduced_cooldown(cooldown)
   return cooldown * 0.75
end

return AceCunningTownBonus
