local PeriodicInteractionTaskGroup = class()
PeriodicInteractionTaskGroup.name = 'periodic_interaction'
PeriodicInteractionTaskGroup.does = 'stonehearth:work'
PeriodicInteractionTaskGroup.priority = 0.82

return stonehearth.ai:create_task_group(PeriodicInteractionTaskGroup)
         :work_order_tag('job')
         :declare_permanent_task('stonehearth_ace:periodic_interaction', { category = 'work' }, 1.0)
