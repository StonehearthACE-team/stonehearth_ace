local TaskTrackerComponent = radiant.mods.require('stonehearth.components.task_tracker.task_tracker_component')
local AceTaskTrackerComponent = class()
local log = radiant.log.create_logger('task_tracker')

function AceTaskTrackerComponent:get_current_task()
   return self._sv.task_activity_name
end

AceTaskTrackerComponent._old_request_task = TaskTrackerComponent.request_task
function AceTaskTrackerComponent:request_task(player_id, category, task_activity_name, task_effect_name)
   local result = self:_old_request_task(player_id, category, task_activity_name, task_effect_name)

   if result then
      radiant.events.trigger(self._entity, 'stonehearth_ace:task_tracker:task_requested', task_activity_name)
   end

   return result
end

AceTaskTrackerComponent._old_cancel_current_task = TaskTrackerComponent.cancel_current_task
function AceTaskTrackerComponent:cancel_current_task(should_reconsider_ai)
   local result = self:_old_cancel_current_task(should_reconsider_ai)

   radiant.events.trigger(self._entity, 'stonehearth_ace:task_tracker:task_canceled', result)
   return result
end

return AceTaskTrackerComponent
