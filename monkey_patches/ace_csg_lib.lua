local Region3 = _radiant.csg.Region3
--local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local ace_csg_lib = {}

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