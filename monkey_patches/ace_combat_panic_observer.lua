local constants = require 'constants'
local log = radiant.log.create_logger('combat')
local CombatPanicObserver = require 'stonehearth.ai.observers.combat_panic_observer'

local AceCombatPanicObserver = class()

AceCombatPanicObserver._ace_old__on_battery = CombatPanicObserver._on_battery
function AceCombatPanicObserver:_on_battery(context)
   if self._entity:get_component('stonehearth:buffs') and self._entity:get_component('stonehearth:buffs'):is_invulnerable() then
      return
   end

   self:_ace_old__on_battery(context)
end

return AceCombatPanicObserver
