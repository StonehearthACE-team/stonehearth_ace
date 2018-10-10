local TaskTrackerComponent = radiant.mods.require('stonehearth.components.task_tracker.task_tracker_component')
local AceTaskTrackerComponent = class()
local log = radiant.log.create_logger('task_tracker')
local HARVEST_ACTION = 'stonehearth:harvest_renewable_resource'

AceTaskTrackerComponent._old_cancel_current_task = TaskTrackerComponent.cancel_current_task
function AceTaskTrackerComponent:cancel_current_task(should_reconsider_ai, keep_auto_harvest_enabled)
   -- if this is a renewable resource node and we're canceling harvesting, also disable auto-harvest
   local renewable = self._entity:get_component('stonehearth:renewable_resource_node')
   if not keep_auto_harvest_enabled and renewable and self:is_activity_requested(HARVEST_ACTION) then
      renewable:set_auto_harvest_enabled(false)
   end
   
   self:_old_cancel_current_task(should_reconsider_ai)
end

return AceTaskTrackerComponent
