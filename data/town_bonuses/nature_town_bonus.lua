local NatureTownBonus = class()

function NatureTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'Banner of Vitality'
   self._sv.description = '<i>This settlement shall be at one with the environment.</i><ul><li>Trees produce 25% more Wood</li><li>Plants and Crops both grow 25% faster</li><li>Plants have 2x their normal Appeal</li></ul>'
end

function NatureTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function NatureTownBonus:initialize_bonus()
   radiant.events.trigger(radiant, 'stonehearth:growth_rate_may_have_changed')
end

function NatureTownBonus:apply_growth_period_bonus(growth_period)
   return growth_period * 0.75
end

function NatureTownBonus:apply_consumed_wood_durability_bonus(durability_to_consume)
   return durability_to_consume / 1.3333
end

--Plant appeal modifier is in constants.json -> VITALITY_PLANT_APPEAL_MULTIPLIER
-- (currently 2x)

return NatureTownBonus
