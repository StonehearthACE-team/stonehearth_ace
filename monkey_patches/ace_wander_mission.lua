local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceWanderMission = class()

function AceWanderMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AceWanderMission
