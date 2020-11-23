local validator = radiant.validator
local TownCallHandler = class()

function TownCallHandler:has_guildmaster_town_bonus(session, response, player_id)
   validator.expect_argument_types({'string'}, player_id)
   local town = stonehearth.town:get_town(player_id)
   local guildmaster = town and town:get_town_bonus('stonehearth:town_bonus:guildmaster')
	response:resolve({ has_guildmaster = guildmaster ~= nil })
end

return TownCallHandler
