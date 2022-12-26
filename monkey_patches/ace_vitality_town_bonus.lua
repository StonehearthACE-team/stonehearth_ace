local VitalityTownBonus = require 'stonehearth.data.town_bonuses.vitality_town_bonus'
local AceVitalityTownBonus = class()

function AceVitalityTownBonus:activate()
   self._json = radiant.resources.load_json('stonehearth_ace:data:town_bonuses:vitality')
   self._growth_period_mult = self._json.growth_period_mult or 1
   self._growth_period_add = self._json.growth_period_add or 0
   self._tree_durability_to_consume_mult = self._json.tree_durability_to_consume_mult or 1
   self._tree_durability_to_consume_add = self._json.tree_durability_to_consume_add or 0
end

function AceVitalityTownBonus:apply_growth_period_bonus(growth_period)
   return growth_period * self._growth_period_mult + self._growth_period_add
end

function AceVitalityTownBonus:apply_consumed_wood_durability_bonus(durability_to_consume)
   return durability_to_consume * self._tree_durability_to_consume_mult + self._tree_durability_to_consume_add
end

--Plant appeal modifier is in constants.json -> VITALITY_PLANT_APPEAL_MULTIPLIER
-- (currently 2x)

return AceVitalityTownBonus
