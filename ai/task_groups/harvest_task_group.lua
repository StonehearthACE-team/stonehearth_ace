local HarvestTaskGroup = class()
HarvestTaskGroup.name = 'harvest'
HarvestTaskGroup.does = 'stonehearth:simple_labor'
HarvestTaskGroup.priority = {0.7, 0.8}

return stonehearth.ai:create_task_group(HarvestTaskGroup)
         :work_order_tag("gather")
         :declare_permanent_task('stonehearth:harvest_resource', { category = "harvest" }, {0, 1})
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "harvest" }, {0, 1})
