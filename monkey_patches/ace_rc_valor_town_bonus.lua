local AceValorTownBonus = class()

local ACE_RECIPES_TO_UNLOCK = {}
ACE_RECIPES_TO_UNLOCK = radiant.resources.load_json('stonehearth_ace:data:recipe_list:rc_valor_town_bonus', true, false)

local RECIPE_UNLOCK_BULLETIN_TITLES = {
   "i18n(rayyas_children:data.gm.campaigns.town_progression.shrine_upgrade_valor.recipe_bulletins.recipe_unlock_weapons_1)",
   "i18n(rayyas_children:data.gm.campaigns.town_progression.shrine_upgrade_valor.recipe_bulletins.recipe_unlock_weapons_2)",
   "i18n(rayyas_children:data.gm.campaigns.town_progression.shrine_upgrade_valor.recipe_bulletins.recipe_unlock_weapons_3)",
}

function AceValorTownBonus:get_recipe_unlocks()
   return ACE_RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return AceValorTownBonus