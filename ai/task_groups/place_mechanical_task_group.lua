local PLACEMENT_TAG = 'mechanical'

local PlacementTaskGroup = class()
PlacementTaskGroup.name = PLACEMENT_TAG .. ' placement'
PlacementTaskGroup.does = 'stonehearth:work'
PlacementTaskGroup.priority = 0.4

return stonehearth.ai:create_task_group(PlacementTaskGroup)
         :work_order_tag("job")
         :declare_permanent_task('stonehearth_ace:place_item_tag_on_structure', {placement_tag = PLACEMENT_TAG}, 0)
         :declare_permanent_task('stonehearth_ace:place_item_type_tag_on_structure', {placement_tag = PLACEMENT_TAG}, 0)
