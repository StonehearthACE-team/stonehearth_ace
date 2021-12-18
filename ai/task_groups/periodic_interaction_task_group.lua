local PeriodicInteractionTaskGroup = class()
PeriodicInteractionTaskGroup.name = 'periodic_interaction'
PeriodicInteractionTaskGroup.does = 'stonehearth:work'
PeriodicInteractionTaskGroup.priority = 0.8

return stonehearth.ai:create_task_group(PeriodicInteractionTaskGroup)
         :work_order_tag('job')
         :declare_multiple_tasks('stonehearth_ace:periodic_interaction', 1.0)
