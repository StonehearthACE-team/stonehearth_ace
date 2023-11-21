local CATEGORY = 'farming'

local HarvestTaskGroup = class()
HarvestTaskGroup.name = 'harvest ' .. CATEGORY
HarvestTaskGroup.does = 'stonehearth:work'
HarvestTaskGroup.priority = {0.48, 0.56}

return stonehearth.ai:create_task_group(HarvestTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:harvest_field', {}, 1)
         :declare_permanent_task('stonehearth:harvest_resource', { category = CATEGORY }, {0.5, 1})
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = CATEGORY }, {0.5, 1})
