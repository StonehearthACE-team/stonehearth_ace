local AceGuildmasterTownBonus = class()

local ACE_RECIPES_TO_UNLOCK = {}
ACE_RECIPES_TO_UNLOCK = radiant.resources.load_json('stonehearth_ace:data:recipe_list:na_guildmaster_town_bonus', true, false)

local RECIPE_UNLOCK_BULLETIN_TITLES = {}

function AceGuildmasterTownBonus:get_recipe_unlocks()
   return ACE_RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return AceGuildmasterTownBonus
