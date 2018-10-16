--[[
   this client service does the following:
   - import modded gameplay settings from a json file
   - provide the modded gameplay settings to the ui on request
   - on load, tell the server what the client settings are
]]

local log = radiant.log.create_logger('gameplay_settings')
local GameplaySettingsService = class()

local _mods_to_update = {}
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
   local mods_to_update = {}
   for mod, settings in pairs(self._settings) do
      mods_to_update[mod] = settings
   end
   _mods_to_update = mods_to_update
   
   self:_update_gameplay_settings_from_config()
end

function GameplaySettingsService:_update_gameplay_settings_from_config()
   local mod, settings = next(_mods_to_update)

   if mod and settings then
      _mods_to_update[mod] = nil
      local settings_to_update = {}
      for name, setting in pairs(settings) do
         settings_to_update[name] = setting
      end
      _settings_to_update = settings_to_update
      self:_update_specific_setting(mod)
   else
      self._settings_are_up_to_date = true
      -- let the server know what all the client settings are
      _radiant.call('stonehearth_ace:set_client_gameplay_settings_command', self._settings)
   end
end

function GameplaySettingsService:_update_specific_setting(mod)
   local name, setting = next(_settings_to_update)

   if mod and setting then
      _settings_to_update[name] = nil
      local key = 'mods.'..mod..'.'..name
      _radiant.call('radiant:get_config', key)
         :done(function(response)
            self._settings[mod][name].value = response[key]
            self:_update_specific_setting(mod)
         end)
   else
      -- finished with this mod, move onto the next one
      self:_update_gameplay_settings_from_config()
   end
end

return GameplaySettingsService