local JobPlacementTaskGroup = class()
JobPlacementTaskGroup.name = 'placement'
JobPlacementTaskGroup.does = 'stonehearth:work'
JobPlacementTaskGroup.priority = {0.40, 0.93}

return stonehearth.ai:create_task_group(JobPlacementTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth_ace:job_place_item_on_structure', {}, 0)
         :declare_permanent_task('stonehearth_ace:job_place_item_type_on_structure_2', {}, 0)
