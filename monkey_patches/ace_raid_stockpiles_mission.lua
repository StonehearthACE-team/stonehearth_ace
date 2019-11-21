local Mission = require 'stonehearth.services.server.game_master.controllers.missions.mission'
local AceRaidStockpilesMission = class()

function AceRaidStockpilesMission:destroy()
   Mission.__user_destroy(self)
   self:stop()
end

return AceRaidStockpilesMission
