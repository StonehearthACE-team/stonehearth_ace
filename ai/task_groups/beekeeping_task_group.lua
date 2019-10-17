local BeekeepingTaskGroup = class()
BeekeepingTaskGroup.name = 'beekeeping'
BeekeepingTaskGroup.does = 'stonehearth:work'
BeekeepingTaskGroup.priority = 0.75

return stonehearth.ai:create_task_group(BeekeepingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:harvest_resource', { category = "beekeeping" }, 1.0)
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "beekeeping" }, 0.0)
