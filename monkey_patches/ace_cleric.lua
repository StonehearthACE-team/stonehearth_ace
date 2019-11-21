local CombatJob = require 'stonehearth.jobs.combat_job'
local AceClericClass = class()

function AceClericClass:destroy()
   if self._sv.is_current_class then
      self:_unregister_with_town()
   end

   CombatJob.__user_destroy(self)
end

return AceClericClass