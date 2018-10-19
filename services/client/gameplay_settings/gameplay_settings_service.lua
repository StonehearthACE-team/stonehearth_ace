--[[
   this client service does the following:
   - import modded gameplay settings from a json file
   - provide the modded gameplay settings to the ui on request
   - on load, tell the server what the client settings are
]]

local log = radiant.log.create_logger('gameplay_settings')
local GameplaySettingsService = class()

function GameplaySettingsService:initialize()
   self._settings_are_up_to_date = false
   self:_load_modded_settings()
   
   self._server_ready_listener = radiant.events.listen(radiant, 'radiant:client:server_ready', self, self._on_server_ready)
end

function GameplaySettingsService:destroy()
   self:destroy_listeners()
end

function GameplaySettingsService:destroy_listeners()
   if self._server_ready_listener then
      self._server_ready_listener:destroy()
      self._server_ready_listener = nil
   end
end

function GameplaySettingsService:_load_modded_settings()
   self._settings = radiant.resources.load_json('stonehearth_ace:data:modded_settings') or {}
end

function GameplaySettingsService:_on_server_ready()
   -- go through settings and update the values in this data structure from the various mods they're in
   self:_update_gameplay_settings_from_config()
end

function GameplaySettingsService:_update_gameplay_settings_from_config()
   self._settings_are_up_to_date = false
   
   for mod, settings in pairs(self._settings) do
      for name, setting in pairs(settings) do
         setting.value = radiant.util.get_global_config('mods.'..mod..'.'..name, setting.default)
      end
   end

   self._settings_are_up_to_date = true
   -- let the server know what all the client settings are
   _radiant.call('stonehearth_ace:set_client_gameplay_settings_command', self._settings)
end

return GameplaySettingsService