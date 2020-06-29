local SoloBasicNeedsTaskGroup = radiant.mods.require('stonehearth.ai.task_groups.solo_basic_needs_task_group')
SoloBasicNeedsTaskGroup:declare_permanent_task('stonehearth_ace:drink', {}, {0.4, 0.8})
return {}