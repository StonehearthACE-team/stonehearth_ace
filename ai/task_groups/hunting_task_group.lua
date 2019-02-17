local HuntingTaskGroup = class()
HuntingTaskGroup.name = 'hunting'
HuntingTaskGroup.does = 'stonehearth:work'
HuntingTaskGroup.priority = 0.57

return stonehearth.ai:create_task_group(HuntingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth_ace:hunt_animal', {category = 'hunt'}, 1.0)