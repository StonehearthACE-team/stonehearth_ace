local AceNaValorTownBonus = class()

local ACE_RECIPES_TO_UNLOCK = {
   ['stonehearth:jobs:mason'] = {
      'signage_decoration:wall_mounted_paw'
   },
   ['stonehearth:jobs:weaver'] = {
      'decorations:rug_pelt_wolf_recipe',
   }
}

local RECIPE_UNLOCK_BULLETIN_TITLES = {
   "i18n(northern_alliance:data.gm.campaigns.town_progression.shrine_upgrade_valor.recipe_bulletins.recipe_unlock_mason)",
   "i18n(northern_alliance:data.gm.campaigns.town_progression.shrine_upgrade_valor.recipe_bulletins.recipe_unlock_weaver)",
}

function AceNaValorTownBonus:get_recipe_unlocks()
   return ACE_RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return AceNaValorTownBonus