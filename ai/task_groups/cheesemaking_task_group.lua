local CheesemakingTaskGroup = class()
CheesemakingTaskGroup.name = 'cheesemaking'
CheesemakingTaskGroup.does = 'stonehearth:work'
CheesemakingTaskGroup.priority = 0.15

return stonehearth.ai:create_task_group(CheesemakingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:harvest_resource', { category = "cheesemaking" }, 1.0)
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "cheesemaking" }, 0.0)
