local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceRaidCropsMission = class()

function AceRaidCropsMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AceRaidCropsMission
