local GameModeCallHandler = class()

function GameModeCallHandler:get_game_mode_json(session, response)
	response:resolve({ game_mode_json = stonehearth.game_creation:get_game_mode_json() })
end

return GameModeCallHandler
