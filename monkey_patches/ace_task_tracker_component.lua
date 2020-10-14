local TaskTrackerComponent = radiant.mods.require('stonehearth.components.task_tracker.task_tracker_component')
local AceTaskTrackerComponent = class()
local log = radiant.log.create_logger('task_tracker')

AceTaskTrackerComponent._ace_old_activate = TaskTrackerComponent.activate
function AceTaskTrackerComponent:activate()
   if self._ace_old_activate then
      self:_ace_old_activate()
   end

   self._json = radiant.entities.get_json(self) or {}
   local destroy_if_task_canceled = self._json.destroy_if_task_canceled
   if destroy_if_task_canceled then
      local tasks = {}
      if radiant.util.is_string(destroy_if_task_canceled) then
         tasks[destroy_if_task_canceled] = true
      else
         for _, task in ipairs(destroy_if_task_canceled) do
            tasks[task] = true
         end
      end

      self._destroy_if_task_canceled = tasks
   end
end

function AceTaskTrackerComponent:get_current_task()
   return self._sv.task_activity_name
end

function AceTaskTrackerComponent:get_current_task_effect_name()
   return self._sv._task_effect_name
end

AceTaskTrackerComponent._ace_old_request_task = TaskTrackerComponent.request_task
function AceTaskTrackerComponent:request_task(player_id, category, task_activity_name, task_effect_name)
   if not self._entity:is_valid() then
      return
   end
   
   local result = self:_ace_old_request_task(player_id, category, task_activity_name, task_effect_name)

   if result then
      radiant.events.trigger(self._entity, 'stonehearth_ace:task_tracker:task_requested', task_activity_name)
   end

   return result
end

AceTaskTrackerComponent._ace_old_cancel_current_task = TaskTrackerComponent.cancel_current_task
function AceTaskTrackerComponent:cancel_current_task(should_reconsider_ai)
   local should_destroy = self._destroy_if_task_canceled and self._destroy_if_task_canceled[self._sv.task_activity_name]
   local result = self:_ace_old_cancel_current_task(should_reconsider_ai)

   radiant.events.trigger(self._entity, 'stonehearth_ace:task_tracker:task_canceled', result)

   if should_destroy and self._entity:is_valid() then
      radiant.entities.destroy_entity(self._entity)
   end
   return result
end

return AceTaskTrackerComponent
