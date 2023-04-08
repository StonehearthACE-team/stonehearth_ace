local XYZRangeSelector = require 'stonehearth_ace.services.client.selection.range_selector'
local PatternXZRegionSelector = require 'stonehearth_ace.services.client.selection.pattern_xz_region_selector'

local SelectionService = require 'stonehearth.services.client.selection.selection_service'
local AceSelectionService = class()

function AceSelectionService:select_xyz_range(reason)
   return XYZRangeSelector(reason)
end

function AceSelectionService:select_pattern_region(reason)
   return PatternXZRegionSelector(reason)
end

function AceSelectionService:select_pattern_designation_region(reason)
   return self:select_pattern_region(reason)
               :require_supported(true)
               :require_unblocked(true)
               :allow_unselectable_support_entities(true)
               :set_find_support_filter(function(result)
                     local entity = result.entity
                     -- make sure we draw zones atop either the terrain, something we've built, or
                     -- something that's solid
                     if entity:get_component('terrain') then
                        return true
                     end
                     if (entity:get_component('stonehearth:construction_data') or
                         entity:get_component('stonehearth:build2:structure')) then
                        return true
                     end
                     local rcs = entity:get_component('region_collision_shape')
                     if rcs and rcs:get_region_collision_type() ~= _radiant.om.RegionCollisionShape.NONE then
                        return stonehearth.selection.FILTER_IGNORE
                     end
                     return stonehearth.selection.FILTER_IGNORE
                  end)
               :set_can_contain_entity_filter(function (entity)
                     return SelectionService.designation_can_contain(entity)
                  end)
end

return AceSelectionService
