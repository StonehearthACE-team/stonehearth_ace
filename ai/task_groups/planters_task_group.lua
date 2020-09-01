local PlantersTaskGroup = class()
PlantersTaskGroup.name = 'planters'
PlantersTaskGroup.does = 'stonehearth:work'
PlantersTaskGroup.priority = { 0, 0.82 }

return stonehearth.ai:create_task_group(PlantersTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth_ace:harvest_herbalist_planter', {}, 1.0)
         :declare_multiple_tasks('stonehearth_ace:plant_herbalist_planter', 0.75)
         :declare_multiple_tasks('stonehearth_ace:clear_herbalist_planter', 0.75)
         :declare_permanent_task('stonehearth_ace:tend_herbalist_planter', {}, 0.5)
