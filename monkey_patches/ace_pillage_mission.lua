local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AcePillageMission = class()

function AcePillageMission:destroy()
   self:stop()
   Mission.__user_destroy(self)
end

return AcePillageMission
