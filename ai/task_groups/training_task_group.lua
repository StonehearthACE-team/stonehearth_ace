local TrainingTaskGroup = class()
TrainingTaskGroup.name = 'training'
TrainingTaskGroup.does = 'stonehearth:work'
TrainingTaskGroup.priority = 0.6

return stonehearth.ai:create_task_group(TrainingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth_ace:training', {}, {0, 1})