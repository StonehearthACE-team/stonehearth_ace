local HerdingTaskGroup = class()
HerdingTaskGroup.name = 'herding'
HerdingTaskGroup.does = 'stonehearth:work'
HerdingTaskGroup.priority = {0.24, 0.82} -- changed from {0.24, 0.40}

return stonehearth.ai:create_task_group(HerdingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth:harvest_resource', { category = "herding" }, 0.9)
         :declare_permanent_task('stonehearth:harvest_renewable_resource', { category = "herding" }, 0.0)
         :declare_permanent_task('stonehearth:collect_animals_for_pasture', {}, 0.0)
         :declare_permanent_task('stonehearth:return_trailing_animals_to_pasture', {}, 0.5)
         :declare_multiple_tasks('stonehearth:find_stray_animal', 0.5)
         :declare_multiple_tasks('stonehearth:feed_pasture_animals', 1.0)
         :declare_multiple_tasks('stonehearth_ace:feed_pasture_trough', 1.0)
