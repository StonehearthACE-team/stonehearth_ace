local BuildTaskGroup = class()
BuildTaskGroup.name = 'build'
BuildTaskGroup.does = 'stonehearth:work'
BuildTaskGroup.priority = {0.36, 0.56}  -- changed from {0.4, 0.56}

return stonehearth.ai:create_task_group(BuildTaskGroup)
         :work_order_tag("build")
         :declare_multiple_tasks('stonehearth_ace:collect_building_material', {0, 0.4})
         :declare_permanent_task('stonehearth:fabricate_chunk', {}, 0.2)
         :declare_multiple_tasks('stonehearth:fabricate_structure', 0.2)
         :declare_multiple_tasks('stonehearth:fabricate_structure_free', 0.2)
         :declare_task('stonehearth:teardown_structure', 1)
         :declare_task('stonehearth:dig_foundation', 0.6)
         :declare_task('stonehearth:build_ladder', 0.2)
         :declare_task('stonehearth:teardown_ladder', 0.6)
         :declare_permanent_task('stonehearth_ace:build_item_type_on_structure', {}, 0.1)
