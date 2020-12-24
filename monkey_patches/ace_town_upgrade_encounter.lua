local TownUpgradeEncounter = require 'stonehearth.services.server.game_master.controllers.encounters.town_upgrade_encounter'
local AceTownUpgradeEncounter = class()

AceTownUpgradeEncounter._ace_old_stage_4_celebrate = TownUpgradeEncounter.stage_4_celebrate
function AceTownUpgradeEncounter:stage_4_celebrate()
   self:_ace_old_stage_4_celebrate()

   if radiant.entities.exists(self._sv.old_facility) then
      local commands = self._sv.old_facility:get_component('stonehearth:commands')
      if commands then
         commands:set_command_enabled('stonehearth:commands:move_item', true)
      end
   end
end

return AceTownUpgradeEncounter
