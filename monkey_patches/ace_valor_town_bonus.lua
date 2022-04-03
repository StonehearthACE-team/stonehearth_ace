local AceValorTownBonus = class()

local ACE_RECIPES_TO_UNLOCK = {
   ['stonehearth:jobs:blacksmith'] = {
      'building_parts:valor_torch',
      'decoration:valor_brazier_large',
      'decoration:wall_hanging_plaque',
      'decoration:valor_war_horn',
      'legendary:steel_frame',
      'legendary:two_handed_sword_valor',
      'legendary:circlet_valor',
   },
   ['stonehearth:jobs:engineer'] = {
      'building_parts:portcullis_valor',
      'legendary:mechanism',
   },
   ['stonehearth:jobs:mason'] = {
      'signage_decoration:statue_knight',
      'signage_decoration:statue_knight_male',
      'legendary:lucid_gem',
      'legendary:giants_shield',
   },
   ['stonehearth:jobs:carpenter'] = {
      'legendary:bow_valor',
      'legendary:giants_face',
   },
   ['stonehearth:jobs:herbalist'] = {
      'legendary:leaf_setting',
   },
   ['stonehearth:jobs:potter'] = {
      'legendary:blazing_inlay',
   },
   ['stonehearth:jobs:weaver'] = {
      'legendary:silver_bowstring',
      'legendary:woven_grip',
   }
}

local RECIPE_UNLOCK_BULLETIN_TITLES = {
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_blacksmith)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_mason)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_engineer)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_1)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_2)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_3)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_4)"
}

function AceValorTownBonus:get_recipe_unlocks()
   return ACE_RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return AceValorTownBonus