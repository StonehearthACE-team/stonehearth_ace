local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceWanderMission = class()

function AceWanderMission:initialize()
   Mission.__user_initialize(self)
   self._sv.points = nil
   self._sv.current_index = 1
end

function AceWanderMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AceWanderMission
