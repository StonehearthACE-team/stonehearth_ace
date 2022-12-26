local StrengthTownBonus = require 'stonehearth.data.town_bonuses.strength_town_bonus'
local rng = _radiant.math.get_default_rng()

local AceStrengthTownBonus = class()

function AceStrengthTownBonus:activate()
   self._json = radiant.resources.load_json('stonehearth_ace:data:town_bonuses:strength')
   self._double_roll_mining_loot_chance = self._json.double_roll_mining_loot_chance or 0.5
end

function AceStrengthTownBonus:should_double_roll_mining_loot()
   return rng:get_real(0, 1) <= self._double_roll_mining_loot_chance
end

return AceStrengthTownBonus
