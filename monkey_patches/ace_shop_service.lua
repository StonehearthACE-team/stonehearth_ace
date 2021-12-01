local validator = radiant.validator
local AceShopService = class()

function AceShopService:trigger_trader_encounter_command(session, response, shop_entity)
   validator.expect_argument_types({'Entity'}, shop_entity)
   local shop_component = shop_entity:get_component('stonehearth_ace:market_stall') or shop_entity:get_component('stonehearth:shop_trigger')
   if shop_component then
      shop_component:trigger_trader_encounter()
   end
end

return AceShopService
