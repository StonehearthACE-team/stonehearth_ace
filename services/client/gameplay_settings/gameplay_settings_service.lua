--[[
   this client service does the following:
   - import modded gameplay settings from a json file
   - provide the modded gameplay settings to the ui on request
   - on load, tell the server what the client settings are
]]

local GameplaySettingsService = class()

local _settings_to_update = {}

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
   self._settings_are_up_to_date = false
   local settings_to_update = {}
   for mod, settings in pairs(self._settings) do
      settings_to_update[mod] = settings
   end
   _settings_to_update = settings_to_update

   self:_request_update_gameplay_settings_from_config()
end

function GameplaySettingsService:_request_update_gameplay_settings_from_config()
   local mod, settings = next(_settings_to_update)

   if mod and settings then
      if mod == 'stonehearth' then
         --[[
            so... in order to reliably access [stonehearth] settings, we need to patch into an existing client service
            because we can't add a call handler to another mod (as far as I can tell)
         ]]
         stonehearth.mod:update_gameplay_settings_from_config(settings)
         _settings_to_update[mod] = nil
         self._settings[mod] = settings
         self:_request_update_gameplay_settings_from_config()
      else
         _radiant.call(mod..':update_gameplay_settings_from_config_command', settings)
            :done(function(result)
               _settings_to_update[mod] = nil
               self._settings[mod] = result.settings
               self:_request_update_gameplay_settings_from_config()
            end)
      end
   else
      self._settings_are_up_to_date = true
      -- let the server know what all the client settings are
      _radiant.call('stonehearth_ace:set_client_gameplay_settings_command', self._settings)
   end
end

return GameplaySettingsService