local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AcePillageMission = class()

function AcePillageMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AcePillageMission
