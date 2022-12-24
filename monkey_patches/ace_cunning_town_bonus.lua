local CunningTownBonus = require 'stonehearth.data.town_bonuses.cunning_town_bonus'
local AceCunningTownBonus = class()

AceCunningTownBonus._ace_old_activate = CunningTownBonus.activate
function AceCunningTownBonus:activate()
   self._json = radiant.resources.load_json('stonehearth_ace:data:town_bonuses:cunning')
   self._trader_gold_mult = self._json.trader_gold_mult or 1
   self._trader_gold_add = self._json.trader_gold_add or 0
   self._trader_quantity_mult = self._json.trader_quantity_mult or 1
   self._trader_quantity_add = self._json.trader_quantity_add or 0
   self._sell_price_mult = self._json.sell_price_mult or 1
   self._sell_price_add = self._json.sell_price_add or 0
   self._road_speed_mult = self._json.road_speed_mult or 1
   self._road_speed_add = self._json.road_speed_add or 0
   self._merchant_cooldown_mult = self._json.merchant_cooldown_mult or 1
   self._merchant_cooldown_add = self._json.merchant_cooldown_add or 0

   self:_ace_old_activate()
end

function AceCunningTownBonus:apply_trader_gold_bonus(base_gold)
   return base_gold * self._trader_gold_mult + self._trader_gold_add
end

function AceCunningTownBonus:apply_trader_quantity_bonus(quantity)
   return quantity * self._trader_quantity_mult + self._trader_quantity_add
end

function AceCunningTownBonus:apply_sell_price_bonus(price)
   return price * self._sell_price_mult + self._sell_price_add
end

function AceCunningTownBonus:apply_road_speed_bonus(speed)
   return speed * self._road_speed_mult + self._road_speed_add
end

--new ACE bonus
function AceCunningTownBonus:apply_merchant_cooldown_bonus(cooldown)
   return cooldown * self._merchant_cooldown_mult + self._merchant_cooldown_add
end

return AceCunningTownBonus
