local BuildTaskGroup = radiant.mods.require('stonehearth.ai.task_groups.build_task_group')
BuildTaskGroup:declare_multiple_tasks('stonehearth_ace:collect_building_material', 0.25)
return {}