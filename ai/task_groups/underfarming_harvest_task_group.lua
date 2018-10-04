local UnderfarmingTaskGroup = class()
UnderfarmingTaskGroup.name = 'underfarming_harvest'
UnderfarmingTaskGroup.does = 'stonehearth:work'
UnderfarmingTaskGroup.priority = {0.48, 0.56}

return stonehearth.ai:create_task_group(UnderfarmingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:harvest_underfield', {}, 1)
         :declare_permanent_task('stonehearth:harvest_resource', { category = "harvest" }, {0.5, 1.0})
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "harvest" }, {0.5, 1.0})         