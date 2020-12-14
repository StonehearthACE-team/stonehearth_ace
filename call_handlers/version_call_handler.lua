local VersionCallHandler = class()

function VersionCallHandler:get_version_info(session, response)
   return stonehearth_ace.version_info
end

function VersionCallHandler:get_game_creation_version_info(session, response)
   response:resolve({version_info = stonehearth.game_creation:get_game_creation_ace_version_info()})
end

return VersionCallHandler
