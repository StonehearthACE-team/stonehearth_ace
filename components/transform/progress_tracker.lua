local DEFAULT_INTERVAL = '5s'
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

function ProgressTracker:start_time_tracking(interval, progress_per_tick)
   self._sv.timer_interval = interval or DEFAULT_INTERVAL
   self._sv.progress_per_tick = progress_per_tick or DEFAULT_PROGRESS_PER_TICK
   self.__saved_variables:mark_changed()

   self:_create_timer()
end

function ProgressTracker:stop_time_tracking()
   self:_destroy_timer()
end

function ProgressTracker:_create_timer()
   self:_destroy_timer()

   if self._sv.timer_interval and self._sv.progress_per_tick and self._sv.progress < self._sv.max_progress then
      self._timer = stonehearth.calendar:set_interval("update progress", self._sv.timer_interval, function()
         self:increment_progress(self._sv.progress_per_tick)
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