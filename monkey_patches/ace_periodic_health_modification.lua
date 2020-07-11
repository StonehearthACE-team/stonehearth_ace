-- Health modification generic class
--
local AcePeriodicHealthModificationBuff = class()

function AcePeriodicHealthModificationBuff:_on_pulse()
   local resources = self._entity:is_valid() and self._entity:get_component('stonehearth:expendable_resources')
   if not resources then
      return
   end

   local health_change = self._tuning.health_change
   local min_health = self._tuning.min_health or 0
   if self._tuning.is_percentage then
      local max_health = resources:get_max_value('health')
      health_change = max_health * health_change
      min_health = max_health * min_health
   end
   
   local current_health = resources:get_value('health')
   local current_guts = resources:get_percentage('guts') or 1
   if current_health <= min_health or current_guts < 1 then
      return  -- don't beat a dead (or incapacitated) horse
   end

   if self._tuning.cannot_kill then
      --if this would kill, leave them at 1 hp instead. "max" and "-" because health_change is negative
      min_health = math.max(min_health, 1)
   end

   health_change = math.max(health_change, -(current_health - min_health))

   radiant.entities.modify_health(self._entity, health_change)
end

return AcePeriodicHealthModificationBuff
