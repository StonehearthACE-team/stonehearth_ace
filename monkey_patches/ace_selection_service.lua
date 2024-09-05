local Point3 = _radiant.csg.Point3
local UNSELECTABLE_FLAG = _radiant.renderer.QueryFlags.UNSELECTABLE
local XYZRangeSelector = require 'stonehearth_ace.services.client.selection.range_selector'
local PatternXZRegionSelector = require 'stonehearth_ace.services.client.selection.pattern_xz_region_selector'

local SelectionService = require 'stonehearth.services.client.selection.selection_service'
local AceSelectionService = class()

function AceSelectionService:get_active_selector()
   for tool, enabled in pairs(self._all_tools) do
      if enabled then
         return tool
      end
   end
end

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

function AceSelectionService:set_selectable(entity, selectable, deselect_if_selected)
   if not entity or not entity:is_valid() then
      return
   end

   local render_entity = _radiant.client.get_render_entity(entity)

   if render_entity then
      if selectable then
         render_entity:remove_query_flag(UNSELECTABLE_FLAG)
      else
         render_entity:add_query_flag(UNSELECTABLE_FLAG)
         if entity == self._selected and deselect_if_selected ~= false then
            self:select_entity(nil, Point3(0, 0, 0))
         end
      end
   end
end

return AceSelectionService
