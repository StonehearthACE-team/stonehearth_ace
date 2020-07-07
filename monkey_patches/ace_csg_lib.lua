local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
--local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local ace_csg_lib = {}

local DIMENSIONS = { 'x', 'y', 'z' }

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

return ace_csg_lib