local TransformTaskGroup = class()
TransformTaskGroup.name = 'transform'
TransformTaskGroup.does = 'stonehearth:work'
TransformTaskGroup.priority = 0.83

return stonehearth.ai:create_task_group(TransformTaskGroup)
         :work_order_tag('job')
         :declare_multiple_tasks('stonehearth_ace:transform_entity', 1.0)
         :declare_multiple_tasks('stonehearth_ace:transform_entity_with_ingredient', 1.0)