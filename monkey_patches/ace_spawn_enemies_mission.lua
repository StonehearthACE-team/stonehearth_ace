local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceSpawnEnemiesMission = class()

function AceSpawnEnemiesMission:destroy()
   self:stop()
   Mission.__user_destroy(self)
end

return AceSpawnEnemiesMission
