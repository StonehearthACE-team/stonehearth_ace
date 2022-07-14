local GameSpeedService = require 'stonehearth.services.server.game_speed.game_speed_service'
local AceGameSpeedService = class()

local log = radiant.log.create_logger('game_speed')

--AceGameSpeedService._ace_old_on_game_load_complete_command = GameSpeedService.on_game_load_complete_command
function AceGameSpeedService:on_game_load_complete_command(session, response)
   if self._wait_for_game_loaded_command then
      self._wait_for_game_loaded_command = nil

      local load_paused = stonehearth.client_state:get_client_gameplay_setting(session.player_id, 'stonehearth_ace', 'load_paused', true)
      if load_paused then
         log:debug('attempting to load game paused (instead of speed %s)...', tostring(self._sv._user_requested_speed))
         -- set the current speed to paused so the ui properly reflects it
         self._sv.curr_speed = 0
         self.__saved_variables:mark_changed()
      else
         log:debug('loading the game normally (at speed %s)', tostring(self._sv._user_requested_speed))
         _radiant.call('radiant:game:set_game_speed', self._sv._user_requested_speed)
      end
   end
end

return AceGameSpeedService
