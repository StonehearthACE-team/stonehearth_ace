local BrewingTaskGroup = class()
BrewingTaskGroup.name = 'brewing'
BrewingTaskGroup.does = 'stonehearth:work'
BrewingTaskGroup.priority = 0.85

return stonehearth.ai:create_task_group(BrewingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:harvest_resource', { category = "brewing" }, 1.0)
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "brewing" }, 0.0)
