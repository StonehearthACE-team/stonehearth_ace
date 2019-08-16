local HerdingTaskGroup = class()
HerdingTaskGroup.name = 'poaching'
HerdingTaskGroup.does = 'stonehearth:work'
HerdingTaskGroup.priority = 0.15

return stonehearth.ai:create_task_group(HerdingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:harvest_resource', { category = "poaching" }, 1.0)
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "poaching" }, 0.0)
