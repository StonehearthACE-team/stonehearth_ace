local SettingsCallHandler = require 'stonehearth.call_handlers.settings_call_handler'
local AceSettingsCallHandler = class()

AceSettingsCallHandler._ace_old_on_client_config_changed = SettingsCallHandler.on_client_config_changed
function AceSettingsCallHandler:on_client_config_changed(session, response, should_show)
   local result = self:_ace_old_on_client_config_changed(session, response, should_show)

   radiant.events.trigger(radiant, 'stonehearth_ace:client_config_changed')

   return result
end

return AceSettingsCallHandler
