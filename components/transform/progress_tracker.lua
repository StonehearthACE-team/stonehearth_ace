local TIMER_INTERVAL = '5s'
local DEFAULT_PROGRESS_PER_TICK = 1

local ProgressTracker = class()

function ProgressTracker:initialize()
   self._sv.progress = 0
end

function ProgressTracker:create(entity, max_progress)
   self._sv.entity = entity
   self._sv.max_progress = max_progress or 1
end

function ProgressTracker:restore()
   self._is_restore = true
end

function ProgressTracker:post_activate()
   if self._is_restore then
      self:_create_timer()
   end
end

function ProgressTracker:destroy()
   self:_destroy_timer()
end

function ProgressTracker:is_finished()
   return self._sv.progress >= self._sv.max_progress
end

function ProgressTracker:get_progress_percentage()
   return self._sv.progress / self._sv.max_progress
end

function ProgressTracker:set_max_progress(max_progress)
   self._sv.max_progress = max_progress or 1
   self.__saved_variables:mark_changed()
end

function ProgressTracker:increment_progress(amount)
   self._sv.progress = math.min(self._sv.max_progress, self._sv.progress + (amount or 1))
   self.__saved_variables:mark_changed()
end

function ProgressTracker:start_time_tracking(total_time)
   if radiant.util.is_string(total_time) then
      total_time = stonehearth.calendar:parse_duration(total_time)
   end
   self._sv.max_progress = total_time
   self.__saved_variables:mark_changed()

   self:_create_timer()
end

function ProgressTracker:stop_time_tracking()
   self:_destroy_timer()
end

function ProgressTracker:_create_timer()
   self:_destroy_timer()

   if self._sv.progress < self._sv.max_progress then
      self._sv._last_update_time = stonehearth.calendar:get_elapsed_time()
      self._timer = stonehearth.calendar:set_interval("update progress", TIMER_INTERVAL, function()
         local current_time = stonehearth.calendar:get_elapsed_time()
         self:increment_progress(current_time - self._sv._last_update_time)
         self._sv._last_update_time = current_time

         if self:is_finished() then
            self:_destroy_timer()
            radiant.events.trigger_async(self, 'stonehearth_ace:progress_tracker:finished')
         end
      end)
   end
end

function ProgressTracker:_destroy_timer()
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
end

return ProgressTracker