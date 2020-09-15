local SoloBasicNeedsTaskGroup = class()
SoloBasicNeedsTaskGroup.name = 'solo basic needs'
SoloBasicNeedsTaskGroup.does = 'stonehearth:top'
SoloBasicNeedsTaskGroup.priority = {0.21, 0.3}

return stonehearth.ai:create_task_group(SoloBasicNeedsTaskGroup)
         :declare_permanent_task('stonehearth:rest_when_injured', {}, {0.45, 0.9})  -- Only humans have actions that perform this
         :declare_permanent_task('stonehearth:goto_sleep', {}, {0.6, 1.0})
         :declare_permanent_task('stonehearth:eat', {}, {0.4, 1.0})
         :declare_permanent_task('stonehearth_ace:drink', {}, {0.0, 0.4})
         :declare_task('stonehearth:trapping_try_steal_bait', 0.2)  -- Only critters have actions that perform this
