--[[
   so... in order to reliably access [stonehearth] settings, we need to patch into an existing client service
   because we can't add a call handler to another mod (as far as I can tell)
]]

local AceModService = class()

function AceModService:update_gameplay_settings_from_config(settings)
   for id, setting in pairs(settings) do
      setting.value = radiant.util.get_config(id, setting.default)
   end
end

return AceModService