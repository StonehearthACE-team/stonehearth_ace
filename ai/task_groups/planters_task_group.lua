local PlantersTaskGroup = class()
PlantersTaskGroup.name = 'planters'
PlantersTaskGroup.does = 'stonehearth:work'
PlantersTaskGroup.priority = { 0.4, 0.84 }

return stonehearth.ai:create_task_group(PlantersTaskGroup)
         :work_order_tag("job")
         --:declare_multiple_tasks('stonehearth_ace:clear_herbalist_planter', 0.25)
         :declare_multiple_tasks('stonehearth_ace:plant_herbalist_planter', 1.0)
         :declare_permanent_task('stonehearth_ace:harvest_herbalist_planter', {}, 0.5)
         :declare_permanent_task('stonehearth_ace:tend_herbalist_planter', {}, 0)
