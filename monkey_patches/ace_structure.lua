local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local build_util = require 'stonehearth.lib.build_util'
local log = radiant.log.create_logger('build.structure')

local Region3 = _radiant.csg.Region3
local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3

local Structure = require 'stonehearth.components.building2.structure'
local AceStructure = class()

function AceStructure:_update_score()
   if not radiant.is_server then
      return
   end

   local score = 0

   -- Scaffolding doesn't have a score.
   if self._sv._is_platform then
      return
   end

   local area = self:get_current_shape_region():get_area()
   local score = 0
   if area > 0 then
      -- Only do this if score > 0 because otherwise score is not a number!
      local net_worth = radiant.entities.get_net_worth(self._entity)
      local item_multiplier = net_worth or self:_get_building_quality()
      score = (area * item_multiplier) ^ 0.7

      score = radiant.math.round(score)
   end
   stonehearth.score:change_score(self._entity, 'net_worth', 'buildings', score)
end

function AceStructure:_get_building_quality()
   local building_comp = self._sv._owning_building and self._sv._owning_building:get_component('stonehearth:build2:building')
   return building_comp and building_comp:get_building_quality()
end

local function _collect_material_prisms(region_w, results)
   local r_by_material = build_util.get_all_material_regions(region_w)

   for _, r in pairs(r_by_material) do
      local mat_region = region_w:intersect_region(r)
      mat_region:set_tag(0)
      if mat_region:get_area() == mat_region:get_bounds():get_area() then
         -- Useful hack.
         mat_region = Region3(mat_region:get_bounds())
      end

      mat_region:optimize('collect material prisms')

      local prisms = csg_lib.convert_to_rectangular_prisms(mat_region)
      for _, c in ipairs(prisms) do
         table.insert(results, region_w:intersect_cube(c))
      end
   end
end

function AceStructure:to_buildable_pieces(terrain_region)
   local origin = self._sv._origin
   local completed = self._dst:get_region():get()

   local remaining = (self._sv._desired_color_region - completed):translated(origin)
   local size = remaining:get_bounds():get_size()

   -- ACE: split based on building terrain region, not _physics check
   local above_ground = remaining
   local below_ground = terrain_region and remaining:intersect_region(terrain_region) or Region3()

   if not below_ground or below_ground:empty() then
      above_ground = remaining
   else
      above_ground = remaining - below_ground
      -- have to do this again because intersect_region can return a region with a different tag
      below_ground = remaining - above_ground
   end

   above_ground:translate(-origin)
   below_ground:translate(-origin)

   local results = {}

   if not self._sv._ends_are_columns then
      _collect_material_prisms(above_ground, results)
      _collect_material_prisms(below_ground, results)
   else
      -- ACE: split up the below-ground parts as well
      for _, region in ipairs({above_ground, below_ground}) do
         local min = region:get_bounds().min
         local max = region:get_bounds().max
         local min_mask = Cube3(min, Point3(min.x + 1, max.y, min.z + 1))
         local max_mask = Cube3(Point3(max.x - 1, min.y, max.z - 1), max)
         _collect_material_prisms(region:intersect_cube(min_mask), results)
         _collect_material_prisms(region:intersect_cube(max_mask), results)
         region:subtract_cube(min_mask)
         region:subtract_cube(max_mask)
         _collect_material_prisms(region, results)
      end

      log:debug('wall building piece regions: %s', radiant.util.table_tostring(results))
   end

   return results
end

return AceStructure
