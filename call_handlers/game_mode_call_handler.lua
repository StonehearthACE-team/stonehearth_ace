local GameModeCallHandler = class()

function GameModeCallHandler:get_game_mode_json(session, response)
	response:resolve({ game_mode_json = stonehearth.game_creation:get_game_mode_json() })
end

function GameModeCallHandler:get_biome_data(session, response)
   local biome = stonehearth.world_generation:get_biome_alias()
   local biome_data = radiant.resources.load_json(biome)
	response:resolve({
      biome = biome,
      biome_data = biome_data,
   })
end

return GameModeCallHandler
