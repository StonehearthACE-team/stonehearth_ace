--[[
   For per-client data that should be saved by the server.
]]

local Point2 = _radiant.csg.Point2
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

-- this function is used to set all gameplay settings; unspecified settings should get deleted
function AceClientState:set_gameplay_settings(settings)
   local all_settings = self:get_all_gameplay_settings()
   for mod, mod_settings in pairs(settings) do
      -- actually, let's just overwrite everything
      -- that's simpler, and it makes sure setting metadata is up-to-date
      all_settings[mod] = mod_settings

      -- local my_settings = self:get_gameplay_settings(mod)

      -- -- remove any saved settings that don't exist in the passed-in data
      -- for field, setting in pairs(my_settings) do
      --    if not mod_settings[field] then
      --       my_settings[field] = nil
      --    end
      -- end
      
      -- -- don't overwrite existing data aside from value
      -- for field, setting in pairs(mod_settings) do
      --    if not my_settings[field] then
      --       my_settings[field] = setting
      --    else
      --       self:_set_gameplay_setting(my_settings, field, setting.value)
      --    end
      -- end
   end

   log:debug('client %s set gameplay settings', self._sv._player_id)
   radiant.events.trigger(radiant, 'stonehearth_ace:client_gameplay_settings_set', self._sv._player_id)
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

function AceClientState:get_build_grid_offset()
   return self._sv._build_grid_offset or Point2.zero
end

function AceClientState:set_build_grid_offset(offset)
   self._sv._build_grid_offset = offset
end

return AceClientState