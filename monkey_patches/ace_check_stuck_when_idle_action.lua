local AceCheckStuckWhenIdle = class()

local log = radiant.log.create_logger('check_stuck_when_idle')

function AceCheckStuckWhenIdle:start_thinking(ai, entity, args)
   if not self._cooldown then
      self._cooldown = stonehearth.calendar:parse_duration(stonehearth.constants.ai.STUCK_CHECK_INTERVAL)
      self._last_check = stonehearth.calendar:get_elapsed_time()
   end
   if not self._movement_reset_listener then
      -- if they're actively moving, then they're not stuck, so make sure there's a small cooldown remaining
      -- so we don't check again immediately after they stop moving
      -- but also make sure the check does happen quickly after movement ends, because that's when they can become stuck
      local cooldown_reset = self._cooldown - stonehearth.calendar:parse_duration(stonehearth.constants.ai.STUCK_CHECK_RESET_PERIOD)
      self._movement_reset_listener = radiant.entities.trace_grid_location(entity, 'check stuck when idle cooldown reset')
         :on_changed(function() self._last_check = stonehearth.calendar:get_elapsed_time() - cooldown_reset end)
   end

   local now = stonehearth.calendar:get_elapsed_time()

   if now - self._last_check >= self._cooldown then
      self._last_check = now
      if stonehearth.physics:is_stuck(entity) then
         ai:set_think_output()
      end
   end
end

function AceCheckStuckWhenIdle:destroy()
   if self._movement_reset_listener then
      self._movement_reset_listener:destroy()
      self._movement_reset_listener = nil
   end
end

return AceCheckStuckWhenIdle
