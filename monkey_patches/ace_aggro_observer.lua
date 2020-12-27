local AggroObserver = require 'stonehearth.ai.observers.aggro_observer'
local AceAggroObserver = class()

local log = radiant.log.create_logger('aggro_observer')

AceAggroObserver._ace_old__is_killable = AggroObserver._is_killable
function AceAggroObserver:_is_killable(target)
   local killable = self:_ace_old__is_killable(target)
   
   -- also check to make sure it's not a training dummy
   if killable then
      if target:get_component('stonehearth_ace:training_dummy') then
         return false
      end
   end

   return killable
end

return AceAggroObserver
