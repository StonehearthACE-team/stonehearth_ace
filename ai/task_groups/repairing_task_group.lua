local RepairinagTaskGroup = class()
RepairinagTaskGroup.name = 'repairing'
RepairinagTaskGroup.does = 'stonehearth:work'
RepairinagTaskGroup.priority = {0.25, 0.8}

return stonehearth.ai:create_task_group(RepairinagTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:repair', {}, {0, 0.8})
         :declare_permanent_task('stonehearth:refill_ammo', {}, 1)
