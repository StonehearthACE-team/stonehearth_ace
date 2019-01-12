local PerformEvolveTaskGroup = class()
PerformEvolveTaskGroup.name = 'perform evolve'
PerformEvolveTaskGroup.does = 'stonehearth:work'
PerformEvolveTaskGroup.priority = 0.15

return stonehearth.ai:create_task_group(PerformEvolveTaskGroup)
         :work_order_tag("haul")
         :declare_permanent_task('stonehearth_ace:perform_evolve', {category = 'evolve'}, 1.0)