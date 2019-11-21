local Node = require 'stonehearth.services.server.game_master.controllers.node'
local AceEncounter = class()

function AceEncounter:destroy()
   if self._sv.script then
      if self._sv.script.destroy then
         self._sv.script:destroy()
      end
      self._sv.script = nil
      self.__saved_variables:mark_changed()
   end
   Node.__user_destroy(self)
end

return AceEncounter
