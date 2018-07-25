local TrainingTaskGroup = class()
TrainingTaskGroup.name = 'training'
TrainingTaskGroup.does = 'stonehearth:work'
TrainingTaskGroup.priority = 0.57

return stonehearth.ai:create_task_group(TrainingTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth_ace:train', {}, {0, 1})