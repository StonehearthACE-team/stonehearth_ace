--[[
   this component is intended for session-based progress tracking for AI or other temporary tasks
   saved variables are only used in order to communicate to the UI, not to save between sessions
   the component will get removed on restore
]]

local DEFAULT_INTERVAL = '5s'
local DEFAULT_PROGRESS_PER_TICK = 1

local ProgressComponent = class()

function ProgressComponent:initialize()
   self._sv.progress = 0
   self._sv.max_progress = 1
end

function ProgressComponent:restore()
   self._is_restore = true
end

function ProgressComponent:post_activate()
   if self._is_restore then
      self._entity:remove_component('stonehearth_ace:progress')
   end
end

function ProgressComponent:destroy()
   self:_destroy_timer()
end

function ProgressComponent:set_activity(activity)
   self._sv.activity = activity
   self.__saved_variables:mark_changed()
end

function ProgressComponent:reset_progress()
   self._sv.progress = 0
   self.__saved_variables:mark_changed()
end

function ProgressComponent:set_max_progress(max_progress)
   self._sv.max_progress = max_progress
   self.__saved_variables:mark_changed()
end

function ProgressComponent:increment_progress(amount)
   self._sv.progress = math.min(self._sv.max_progress, self._sv.progress + (amount or 1))
   self.__saved_variables:mark_changed()
end

function ProgressComponent:start_time_tracking(interval, progress_per_tick)
   self._sv.timer_interval = interval or DEFAULT_INTERVAL
   self._sv.progress_per_tick = progress_per_tick or DEFAULT_PROGRESS_PER_TICK
   self.__saved_variables:mark_changed()

   self:_create_timer()
end

function ProgressComponent:_create_timer()
   self:_destroy_timer()

   if self._sv.timer_interval and self._sv.progress_per_tick and self._sv.progress < self._sv.max_progress then
      self._timer = stonehearth.calendar:set_interval("update progress", self._sv.timer_interval, function()
         self:increment_progress(self._sv.progress_per_tick)
         if self._sv.progress == self._sv.max_progress then
            self:_destroy_timer()
         end
      end)
   end
end

function ProgressComponent:_destroy_timer()
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
end

return ProgressComponent