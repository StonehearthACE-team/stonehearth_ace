local validator = radiant.validator
local AdvancedPlacementCallHandler = class()

function AdvancedPlacementCallHandler:update_client_connections_command(session, response, args)
   stonehearth_ace.connection_client:update_client_connections(args and args.types)
end

return AdvancedPlacementCallHandler