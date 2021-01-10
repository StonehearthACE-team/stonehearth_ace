-- ACE: added support for shared cooldowns

local CombatStateComponent = require 'stonehearth.components.combat_state.combat_state_component'
local AceCombatStateComponent = class()

function AceCombatStateComponent:in_cooldown(name, shared_cooldown_name)
   local in_cd = self:get_cooldown_end_time(name) ~= nil
   if not in_cd and shared_cooldown_name then
      return self:get_cooldown_end_time(shared_cooldown_name) ~= nil
   end
   return in_cd
end

AceCombatStateComponent._ace_old_get_cooldown_end_time = CombatStateComponent.get_cooldown_end_time
function AceCombatStateComponent:get_cooldown_end_time(name, shared_cooldown_name)
   local end_time = self:_ace_old_get_cooldown_end_time(name)
   if shared_cooldown_name then
      local shared_end_time = self:_ace_old_get_cooldown_end_time(shared_cooldown_name)
      if end_time or shared_end_time then
         return math.max(end_time or shared_end_time, shared_end_time or end_time)
      end
   end

   return end_time
end

return AceCombatStateComponent
