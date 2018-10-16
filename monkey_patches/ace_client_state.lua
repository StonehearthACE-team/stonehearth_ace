--[[
   For per-client data that should be saved by the server.
]]

local log = radiant.log.create_logger('client_state')

local AceClientState = class()

function AceClientState:get_all_gameplay_settings()
   local settings = self._sv._gameplay_settings
   if not settings then
      settings = {}
      self._sv._gameplay_settings = settings
   end

   return settings
end

function AceClientState:get_gameplay_settings(mod)
   local all_settings = self:get_all_gameplay_settings()
   
   if not mod then
      return all_settings
   else
      local settings = all_settings[mod]
      if not settings then
         settings = {}
         self._sv._gameplay_settings[mod] = settings
      end

      return settings
   end
end

function AceClientState:get_gameplay_setting(mod, field)
   local my_settings = self:get_gameplay_settings(mod)
   local setting = my_settings[field]
   if setting then
      return setting.value
   else
      return nil
   end
end

function AceClientState:set_gameplay_settings(settings)
   for mod, mod_settings in pairs(settings) do
      local my_settings = self:get_gameplay_settings(mod)
      
      -- don't delete any unspecified settings (i.e., nil); just set whatever's included
      for field, setting in pairs(mod_settings) do
         if not my_settings[field] then
            my_settings[field] = setting
         else
            self:_set_gameplay_setting(my_settings, field, setting.value)
         end
      end
   end
end

function AceClientState:set_gameplay_setting(mod, field, value)
   local my_settings = self:get_gameplay_settings(mod)
   self:_set_gameplay_setting(my_settings, field, value)
end

function AceClientState:_set_gameplay_setting(settings, field, value)
   local setting = settings[field]
   if not setting then
      setting = {}
      settings[field] = setting
   end
   setting.value = value
   return setting
end

function AceClientState:reset_gameplay_setting()
   self._sv._gameplay_settings = {}
end

return AceClientState