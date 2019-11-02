local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceSpawnEnemiesMission = class()

function AceSpawnEnemiesMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AceSpawnEnemiesMission
