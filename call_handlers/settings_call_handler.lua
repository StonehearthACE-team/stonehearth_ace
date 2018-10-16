local validator = radiant.validator
local SettingsCallHandler = class()

function SettingsCallHandler:get_all_client_gameplay_settings_command(session, response)
   local settings = stonehearth.client_state:get_client_gameplay_settings(session.player_id)
   return {settings = settings}
end

function SettingsCallHandler:set_client_gameplay_settings_command(session, response, settings)
   validator.expect_argument_types({'table'}, settings)

   stonehearth.client_state:set_client_gameplay_settings(session.player_id, settings)
end

function SettingsCallHandler:set_client_gameplay_setting_command(session, response, mod, field, value)
   validator.expect_argument_types({'string', 'string'}, mod, field)

   stonehearth.client_state:set_client_gameplay_setting(session.player_id, mod, field, value)
end

return SettingsCallHandler