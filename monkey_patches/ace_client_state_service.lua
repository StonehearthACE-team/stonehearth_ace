local log = radiant.log.create_logger('client_state_service')

local AceClientStateService = class()

function AceClientStateService:get_client_gameplay_settings(player_id, mod)
   local state = self:get_client_state(player_id)
   return state and state:get_gameplay_settings(mod)
end

function AceClientStateService:get_client_gameplay_setting(player_id, mod, field, default)
   local state = self:get_client_state(player_id)
   local setting = state and state:get_gameplay_setting(mod, field)
   if setting == nil then
      return default
   else
      return setting
   end
end

function AceClientStateService:set_client_gameplay_settings(player_id, settings)
   local state = self:get_client_state(player_id)
   state:set_gameplay_settings(settings)
end

function AceClientStateService:set_client_gameplay_setting(player_id, mod, field, value)
   local state = self:get_client_state(player_id)
   local setting = state:set_gameplay_setting(mod, field, value)
end

function AceClientStateService:get_build_grid_offset(player_id)
   local state = self:get_client_state(player_id)
   return state and state:get_build_grid_offset()
end

function AceClientStateService:set_build_grid_offset(player_id, offset)
   local state = self:get_client_state(player_id)
   return state and state:set_build_grid_offset(offset)
end

return AceClientStateService