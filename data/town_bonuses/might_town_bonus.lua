local rng = _radiant.math.get_default_rng()

local MightTownBonus = class()

function MightTownBonus:initialize()
   self._sv.player_id = nil
   self._sv.display_name = 'Banner of Strength'
   self._sv.description = '<i>This settlement will grow strong through earth and steel.</i><ul><li>Mining gives 50% more Ore, Stone, and Clay</li><li>Hearthlings no longer mind cramped spaces</li></ul>'
end

function MightTownBonus:create(player_id)
   self._sv.player_id = player_id
end

function MightTownBonus:should_double_roll_mining_loot()
   return rng:get_real(0, 1) <= 0.50
end

return MightTownBonus
