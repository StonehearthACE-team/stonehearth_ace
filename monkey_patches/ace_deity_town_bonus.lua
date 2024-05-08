local AceDeityTownBonus = class()

local ACE_RECIPES_TO_UNLOCK = {}
ACE_RECIPES_TO_UNLOCK = radiant.resources.load_json('stonehearth_ace:data:recipe_list:deity_town_bonus', true, false)


function AceDeityTownBonus:get_recipe_unlocks()
   return ACE_RECIPES_TO_UNLOCK, RECIPE_UNLOCK_BULLETIN_TITLES
end

return AceDeityTownBonus
