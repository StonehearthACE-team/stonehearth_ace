local UnderfarmingTaskGroup = class()
UnderfarmingTaskGroup.name = 'underfarming'
UnderfarmingTaskGroup.does = 'stonehearth:work'
UnderfarmingTaskGroup.priority = {0.48, 0.56}

return stonehearth.ai:create_task_group(UnderfarmingTaskGroup)
         :work_order_tag("job")
         -- Plant and till HAVE TO BE THE SAME or the performance implications are staggering -yshan
         -- TODO: Is the above still true?
         :declare_permanent_task('stonehearth_ace:plant_undercrop', {}, 0)
         :declare_permanent_task('stonehearth_ace:till_entire_underfield', {}, 0)
         :declare_permanent_task('stonehearth_ace:harvest_underfield', {}, 1)
         