local DrinkingTaskGroup = class()
DrinkingTaskGroup.name = 'drinking'
DrinkingTaskGroup.does = 'stonehearth:top'
DrinkingTaskGroup.priority = {0.01, 0.25}

return stonehearth.ai:create_task_group(DrinkingTaskGroup)
         :declare_permanent_task('stonehearth_ace:drink', {}, {0.45, 1.0})

         