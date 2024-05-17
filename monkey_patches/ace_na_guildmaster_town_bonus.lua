local AceGuildmasterTownBonus = class()

local ACE_RECIPES_TO_UNLOCK = {}
ACE_RECIPES_TO_UNLOCK = radiant.resources.load_json('stonehearth_ace:data:recipe_list:na_guildmaster_town_bonus', true, false)

local RECIPE_UNLOCK_BULLETIN_TITLES = {}

function AceGuildmasterTownBonus:get_adjusted_item_quality_chances()
   -- Replaces constants.crafting.ITEM_QUALITY_CHANCES when the bonus is in effect.
   return {
      {{1, 1}},
      {{1, 1}},
      {{1, 0.95}, {2, 0.05}},
      {{1, 0.9}, {2, 0.10}},
      {{1, 0.85}, {2, 0.07}, {3, 0.06}, {4, 0.02}},
      {{1, 0.80}, {2, 0.08}, {3, 0.07}, {4, 0.05}}
   }
end

function AceGuildmasterTownBonus:get_max_crafting_quality()
   return stonehearth.constants.item_quality.MASTERWORK or 4
end

function AceGuildmasterTownBonus:get_recipe_unlocks()
   return ACE_RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return AceGuildmasterTownBonus
