local VersionCallHandler = class()

function VersionCallHandler:get_version_info_command(session, response)
   return stonehearth_ace.version_info
end

return VersionCallHandler
