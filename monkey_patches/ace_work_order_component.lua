local AceWorkOrderComponent = class()

local WORK_ORDER_STATUS = {
   ENABLED = 'enabled',
   DISABLED = 'disabled',
   LOCKED = 'locked'
}

function AceWorkOrderComponent:is_work_order_enabled(work_order_name)
   if self._sv.work_order_statuses[work_order_name] == WORK_ORDER_STATUS.DISABLED then
      return false
   end

   -- Faction-wide setting overrides entity-level setting.
   local player_id = self._player_id
   local pop = player_id and stonehearth.population:get_population(player_id)
   if pop and pop:is_work_order_suspended(work_order_name) then
      return false
   end

   return true
end

return AceWorkOrderComponent
