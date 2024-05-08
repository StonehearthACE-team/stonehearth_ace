local AceValorTownBonus = class()

local ACE_RECIPES_TO_UNLOCK = {}
ACE_RECIPES_TO_UNLOCK = radiant.resources.load_json('stonehearth_ace:data:recipe_list:valor_town_bonus', true, false)

local RECIPE_UNLOCK_BULLETIN_TITLES = {
   'i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_1)',
   'i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_2)',
   'i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_3)',
   'i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_4)',
   'i18n(stonehearth_ace:data.gm.campaigns.town_progression.ace_valor_reached.recipe_unlock_blacksmith)',
   'i18n(stonehearth_ace:data.gm.campaigns.town_progression.ace_valor_reached.recipe_unlock_weaver)',
   'i18n(stonehearth_ace:data.gm.campaigns.town_progression.ace_valor_reached.recipe_unlock_engineer)',
   'i18n(stonehearth_ace:data.gm.campaigns.town_progression.ace_valor_reached.recipe_unlock_geomancer)',
}

function AceValorTownBonus:get_recipe_unlocks()
   return ACE_RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return AceValorTownBonus