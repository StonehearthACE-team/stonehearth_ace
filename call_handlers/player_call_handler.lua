local validator = radiant.validator
local PlayerCallHandler = class()

function PlayerCallHandler:are_player_ids_hostile(session, response, party_a, party_b)
	validator.expect_argument_types({'string', 'string'}, party_a, party_b)
	response:resolve({ are_hostile = stonehearth.player:are_player_ids_hostile(party_a, party_b) })
end

return PlayerCallHandler
