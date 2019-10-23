local Node = require 'stonehearth.services.server.game_master.controllers.node'
local AceArc = class()

function AceArc:initialize()
   Node.__user_initialize(self)
   self._sv.running_encounters = {}
end

return AceArc
