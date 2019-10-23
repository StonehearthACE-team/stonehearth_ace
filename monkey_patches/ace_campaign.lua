local Node = require 'stonehearth.services.server.game_master.controllers.node'
local AceCampaign = class()

function AceCampaign:initialize()
   Node.__user_initialize(self)
   -- Keep track of arc nodelists for this campaign
   self._sv._nodelists = {}
   self._sv.counters = {}  -- Campaign-global variables used to gate encounters.
end

return AceCampaign
