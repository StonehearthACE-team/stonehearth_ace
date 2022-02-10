local DefendMelee = require 'stonehearth.ai.actions.combat.defend_melee_action'
local AceDefendMelee = class()

local DEFENSE_POSTURE_BUFF = 'stonehearth_ace:buffs:guarding'

function AceDefendMelee:start(ai, entity, args)
   radiant.entities.add_buff(entity, DEFENSE_POSTURE_BUFF)
end

AceDefendMelee._ace_old_stop = DefendMelee.stop
function AceDefendMelee:stop(ai, entity, args)
   radiant.entities.remove_buff(entity, DEFENSE_POSTURE_BUFF)
   self:_ace_old_stop(ai, entity, args)
end

return AceDefendMelee
