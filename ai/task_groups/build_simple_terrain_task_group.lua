local PLACEMENT_TAG = 'simple_terrain'

local BuildTaskGroup = class()
BuildTaskGroup.name = PLACEMENT_TAG .. ' build'
BuildTaskGroup.does = 'stonehearth:work'
BuildTaskGroup.priority = 0.4

return stonehearth.ai:create_task_group(BuildTaskGroup)
         :work_order_tag("build")
         :declare_permanent_task('stonehearth_ace:build_item_type_tag_on_structure', {placement_tag = PLACEMENT_TAG}, 0)
