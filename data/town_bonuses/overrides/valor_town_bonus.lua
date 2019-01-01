local ValorTownBonus = class()

local RECIPES_TO_UNLOCK = {
   ['stonehearth:jobs:blacksmith'] = {
      'building_parts:valor_torch',
      'building_parts:fence_gate_iron',
      'decoration:valor_brazier_large',
      'decoration:wall_hanging_plaque',
      'decoration:valor_war_horn',
      'legendary:steel_frame',
      'legendary:two_handed_sword_valor',
      'legendary:circlet_valor',
	  'legendary:legendary_mail',
	  'legendary:legendary_buckle',
   },
   ['stonehearth:jobs:engineer'] = {
      'building_parts:portcullis_valor',
      'legendary:mechanism',
	  'legendary:legendary_chainmail',
	  'legendary:legendary_mace',
   },
   ['stonehearth:jobs:mason'] = {
      'signage_decoration:statue_knight',
      'signage_decoration:statue_knight_male',
      'signage_decoration:window_arrow_short',
      'signage_decoration:valor_window_arrow_tall',
      'signage_decoration:valor_window_frame_barred',
      'signage_decoration:valor_window_frame_xlarge',
      'legendary:lucid_gem',
      'legendary:giants_shield',
	  'legendary:legendary_headpiece',
   },
   ['stonehearth:jobs:carpenter'] = {
      'legendary:bow_valor',
      'legendary:giants_face',
	  'legendary:legendary_handle',
   },
   ['stonehearth:jobs:herbalist'] = {
      'legendary:leaf_setting',
	  'legendary:legendary_parchment',
   },
   ['stonehearth:jobs:geomancer'] = {
      'legendary:legendary_silk',
	  'legendary:legendary_tome',
   },
   ['stonehearth:jobs:potter'] = {
      'legendary:blazing_inlay',
   },
   ['stonehearth:jobs:cook'] = {
      'legendary:legendary_ink',
   },
   ['stonehearth:jobs:weaver'] = {
      'legendary:silver_bowstring',
      'legendary:woven_grip',
	  'legendary:legendary_hood',
	  'legendary:legendary_cape',
   }
}

local RECIPE_UNLOCK_BULLETIN_TITLES = {
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_blacksmith)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_mason)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_engineer)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_1)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_2)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_3)",
   "i18n(stonehearth:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_4)",
   "i18n(stonehearth_ace:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_5)",
   "i18n(stonehearth_ace:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_6)",
   "i18n(stonehearth_ace:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_7)",
   "i18n(stonehearth_ace:data.gm.campaigns.trader.valor_tier_2_reached.recipe_unlock_weapons_8)"
}

function ValorTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'i18n(stonehearth:data.gm.campaigns.town_progression.shrine_choice.valor.name)'
   self._sv.description = 'i18n(stonehearth:data.gm.campaigns.town_progression.shrine_choice.valor.description)'
end

function ValorTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function ValorTownBonus:initialize_bonus()
   --unlock the new epic weapon recipes
end

function ValorTownBonus:get_recipe_unlocks()
   return RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return ValorTownBonus

