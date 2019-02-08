local PlayerService = require 'stonehearth.services.server.player.player_service'
local AcePlayerService = class()

--If the kingdom is not already specified for this player, add it now
AcePlayerService._ace_old_add_kingdom = PlayerService.add_kingdom
function AcePlayerService:add_kingdom(player_id, kingdom)
   self:_ace_old_add_kingdom(player_id, kingdom)

   radiant.events.trigger(radiant, 'radiant:player_kingdom_assigned', {player_id = player_id})
end

return AcePlayerService
