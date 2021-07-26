local FarmingTaskGroup = radiant.mods.require('stonehearth.ai.task_groups.farming_task_group')
FarmingTaskGroup:declare_multiple_tasks('stonehearth_ace:fertilize_field', 0)
FarmingTaskGroup:declare_permanent_task('stonehearth:harvest_resource', { category = "farming" }, {0.6, 1.0})
FarmingTaskGroup:declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "farming" }, {0.6, 1.0})     
return {}