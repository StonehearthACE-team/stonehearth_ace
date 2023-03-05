local AceWaitForNetWorthEncounter = class()

function AceWaitForNetWorthEncounter:_start_check_net_worth_interval()
   if self:_check_net_worth() then
      return
   end

   local interval = '1h'
   if self._sv.info then
      interval = self._sv.info.interval or '1h'
   end
   self._sv.timer = stonehearth.calendar:set_persistent_interval("WaitForNetWorthEncounter check_net_worth ", interval, radiant.bind(self, '_check_net_worth'))
   self.__saved_variables:mark_changed()
end

function AceWaitForNetWorthEncounter:_check_net_worth()
   local threshold = self._sv.threshold
   local total = self:_get_current_net_worth()
   log:info('checking net worth score.  %d >? %d', total, threshold)
   if total > threshold then
      local ctx = self._sv.ctx
      log:info('triggering next edge')
      ctx.arc:trigger_next_encounter(ctx)
      return true
   end
end

return AceWaitForNetWorthEncounter
