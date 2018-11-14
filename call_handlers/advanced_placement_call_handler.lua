local validator = radiant.validator
local AdvancedPlacementCallHandler = class()

function AdvancedPlacementCallHandler:update_client_connections_command(session, response)
   stonehearth_ace.connection_client:update_client_connections()
end

return AdvancedPlacementCallHandler