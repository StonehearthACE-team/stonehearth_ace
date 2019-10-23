local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceRaidCropsMission = class()

function AceRaidCropsMission:initialize()
   Mission.__user_initialize(self)
   self._sv.update_orders_timer = nil
end

function AceRaidCropsMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AceRaidCropsMission
