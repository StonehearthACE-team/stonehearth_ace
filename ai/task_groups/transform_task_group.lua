local TransformTaskGroup = class()
TransformTaskGroup.name = 'transform'
TransformTaskGroup.does = 'stonehearth:work'
TransformTaskGroup.priority = 0.15

return stonehearth.ai:create_task_group(TransformTaskGroup)
         :work_order_tag("haul")
         :declare_permanent_task('stonehearth_ace:transform', {category = 'transform'}, 1.0)