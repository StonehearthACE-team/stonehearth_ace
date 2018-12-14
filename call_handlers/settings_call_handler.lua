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

function SettingsCallHandler:terrain_slice_buildings_setting_changed(session, response)
   stonehearth.subterranean_view:terrain_slice_buildings_setting_changed()
end

function SettingsCallHandler:water_signal_update_frequency_setting_changed(session, response, frequency)
   if session.player_id == _radiant.sim.get_host_player_id() then
      stonehearth_ace.water_signal:set_update_frequency(frequency)
   end
end

return SettingsCallHandler