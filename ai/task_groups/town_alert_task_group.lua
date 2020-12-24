--[[
   ACE: reduced priority to below rescue priority
   if you want to avoid rescuing people while town alert is on, you can disable auto-rescue and cancel any current rescues
]]

local TownAlertTaskGroup = class()
TownAlertTaskGroup.name = 'town alert'
TownAlertTaskGroup.does = 'stonehearth:combat'
TownAlertTaskGroup.priority = {0, 0.6}   -- {0, 0.85}

return stonehearth.ai:create_task_group(TownAlertTaskGroup)
         :work_order_tag("alert_mode")
         :declare_task('stonehearth:town_alert:run_to_safety', 1)
         :declare_task('stonehearth:town_alert:stand_ground', 0)
