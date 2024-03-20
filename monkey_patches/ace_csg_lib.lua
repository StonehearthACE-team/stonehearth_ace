local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
--local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local ace_csg_lib = {}

local DIMENSIONS = { 'x', 'y', 'z' }

-- same as are_equivalent_regions except ignores tags
function ace_csg_lib.are_same_shape_regions(region_a, region_b)
   if not region_a then
      if not region_b then
         return true
      else
         return false
      end
   elseif not region_b then
      return false
   end
   
   local area_a = region_a:get_area()
   local area_b = region_b:get_area()

   if area_a ~= area_b then
      return false
   end

   local intersection = region_a:intersect_region(region_b)

   return intersection:get_area() == area_a
end

-- create a cube that truly spans p0 and p1 inclusive
function ace_csg_lib.create_min_cube(p0, p1, tag)
   assert(p0 and p1)
   local min, max = Point3(p0), Point3(p1)
   tag = tag or 0

   for _, d in ipairs(DIMENSIONS) do
      if min[d] > max[d] then
         min[d], max[d] = max[d], min[d]
      end
   end

   return Cube3(min, max, tag)
end

function ace_csg_lib.create_directional_cube(p0, p1, direction, tag)
   -- if a direction is specified, use its x/y/z signs for adjusting the min/max
   assert(p0 and p1)
   local min, max = Point3(p0), Point3(p1)
   tag = tag or 0

   for _, d in ipairs(DIMENSIONS) do
      if min[d] > max[d] then
         min[d], max[d] = max[d], min[d]
      end

      if direction and direction[d] < 0 then
         min[d] = min[d] - 1
      else
         max[d] = max[d] + 1
      end
   end

   return Cube3(min, max, tag)
end

function ace_csg_lib.get_region_headprint(region)
   local headprint = Region3()
   local max_y = nil

   for cube in region:each_cube() do
      local cube_max_y = cube.max.y

      if not max_y or cube_max_y > max_y then
         headprint:clear()
         max_y = cube_max_y
      end

      if cube_max_y == max_y then
         local slice = cube:get_face(Point3.unit_y)
         headprint:add_cube(slice)
      end
   end

   return headprint
end

-- if new_region is specified, assume region is already vertically optimized and we're just adding the one cube
-- otherwise assume region is optimized for no overlap and iterate through all but the first cube
function ace_csg_lib.get_vertically_optimized_region(region, new_region)
   local optimized_region = Region3()
   
   if new_region then
      optimized_region:add_region(region)
      ace_csg_lib._add_region_to_vertically_optimized_region(optimized_region, new_region)
   elseif not region:empty() then
      optimized_region:add_cube(region:get_rect(0))
      for i = 1, region:get_num_rects() - 1 do
         ace_csg_lib._add_new_cube_to_vertically_optimized_region(optimized_region, region:get_rect(i))
      end
   end

   -- optimize should now just join together qualifying adjacent neighboring "columns"
   optimized_region:optimize('vertically optimized region')
   return optimized_region
end

function ace_csg_lib._add_region_to_vertically_optimized_region(region, new_region)
   -- we only want to deal with the part of the new cube that's actually new and not already overlapping the existing region
   -- this way we avoid trivially splitting cubes over horizontal overlaps
   local new_cube_r = new_region - region
   if new_cube_r:empty() then
      return
   end

   -- this is probably overkill, but make sure the area that we're going to be adding doesn't have any internal overlap
   new_cube_r:optimize('adding to vertically optimized region')
   for cube in new_cube_r:each_cube() do
      ace_csg_lib._add_new_cube_to_vertically_optimized_region(region, cube)
   end
end

-- this function assumes new_cube has positive area and has no intersection with region
function ace_csg_lib._add_new_cube_to_vertically_optimized_region(region, new_cube)
   local new_cube_r = Region3(new_cube)
   local extr_reg = new_cube_r:extruded('y', 1, 1)
   local new_cube_min_y = new_cube.min.y
   local new_cube_max_y = new_cube.max.y

   local removals = Region3()
   local additions = Region3()

   for cube in region:each_cube() do
      local intersection = extr_reg:intersect_cube(cube)
      if not intersection:empty() then
         -- determine the overlap, then extend that overlap to the min and max y of cube and new_cube
         -- a first iteration can rely on the intersection being a cube, but further iterations can't
         -- since the original new_cube didn't overlap anything but the vertical extrusion does,
         -- we know that only the top or bottom of each cube is overlapping with the opposite of the other
         local min_y = math.min(cube.min.y, new_cube_min_y)
         local max_y = math.max(cube.max.y, new_cube_max_y)
         local bounds = intersection:get_bounds()
         local overlap = intersection:extruded('y', bounds.min.y - min_y, max_y - bounds.max.y)

         local old_remainder = Region3(cube) - overlap
         new_cube_r:subtract_region(overlap)

         removals:add_cube(cube)
         additions:add_region(old_remainder)
         additions:add_region(overlap)

         if new_cube_r:empty() then
            break
         end
      end
   end

   region:subtract_region(removals)
   region:add_region(additions)
   region:add_region(new_cube_r)
end

return ace_csg_lib