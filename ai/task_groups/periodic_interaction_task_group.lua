local PeriodicInteractionTaskGroup = class()
PeriodicInteractionTaskGroup.name = 'periodic interaction'
PeriodicInteractionTaskGroup.does = 'stonehearth:work'
PeriodicInteractionTaskGroup.priority = 0.82

return stonehearth.ai:create_task_group(PeriodicInteractionTaskGroup)
         :work_order_tag('job')
         :declare_multiple_tasks('stonehearth_ace:periodic_interaction', 1.0)
         :declare_multiple_tasks('stonehearth_ace:periodic_interaction_with_ingredient', 1.0)
-- TODO: have a separate "interact with ingredient" action
-- restructure to use task tracker component like transform
