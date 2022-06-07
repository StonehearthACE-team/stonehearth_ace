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

function SettingsCallHandler:issue_party_commands_when_job_disabled_setting_changed(session, response)
   -- go through all parties for that player and apply/cancel party commands for any members with job disabled
   local pop = stonehearth.population:get_population(session.player_id)
   if pop then
      pop:reconsider_all_individual_party_commands()
   end
end

function SettingsCallHandler:title_selection_criteria_changed(session, response, criteria_change)
   radiant.events.trigger(radiant, 'title_selection_criteria_changed', criteria_change)
end

function SettingsCallHandler:terrain_slice_buildings_setting_changed(session, response)
   stonehearth.subterranean_view:terrain_slice_buildings_setting_changed()
end

function SettingsCallHandler:water_signal_update_frequency_setting_changed(session, response, frequency)
   if session.player_id == _radiant.sim.get_host_player_id() then
      stonehearth_ace.water_signal:set_update_frequency(frequency)
   end
end

function SettingsCallHandler:show_farm_water_regions_setting_changed(session, response, show)
   radiant.events.trigger(radiant, 'show_farm_water_regions_setting_changed', show)
end

function SettingsCallHandler:show_connector_regions_setting_changed(session, response, show)
   radiant.events.trigger(radiant, 'show_connector_regions_setting_changed', show)
end

function SettingsCallHandler:get_storage_filter_custom_presets_command(session, response)
   local settings_folder = radiant.mods.enum_objects('settings')
   local presets = {}
   if settings_folder.storage_filter_custom_presets then
      presets = radiant.mods.read_object('settings/storage_filter_custom_presets') or {}
   end

   -- check if we still have custom presets saved to user_settings.json
   local config = radiant.util.get_config('storage_filter_custom_presets')
   if config then
      -- if so, merge them into the current presets, update the saved_objects version, and clear out the user_settings.json version
      for id, preset in pairs(config) do
         presets[id] = preset
      end

      self:set_storage_filter_custom_presets_command(session, response, presets)
      -- have to do this because radiant.util.set_config asserts a non-nil setting
      radiant.util.set_global_config('mods.stonehearth_ace.storage_filter_custom_presets', nil)
   end

   response:resolve({ result = presets })
end

function SettingsCallHandler:set_storage_filter_custom_presets_command(session, response, presets)
   radiant.mods.write_object('settings/storage_filter_custom_presets', presets or {})
end

return SettingsCallHandler