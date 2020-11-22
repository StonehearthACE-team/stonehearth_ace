local build_util = require 'stonehearth.lib.build_util'
local ace_build_util = {}

function ace_build_util.get_all_material_counts(color_region)
   local all_material_counts = {}

   for cube in color_region:each_cube() do
      local tag = cube.tag
      local material = build_util.tag_to_material(tag)
      local count = all_material_counts[material] or 0
      all_material_counts[material] = count + cube:get_area()
   end

   return all_material_counts
end

return ace_build_util
