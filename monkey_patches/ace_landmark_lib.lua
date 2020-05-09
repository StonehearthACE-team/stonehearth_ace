local Region3 = _radiant.csg.Region3
local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local AceLandmarkLib = {}

-- Take a list of water regions, merge them together to a single region, split them into continguous regions, then create them.
function AceLandmarkLib._create_water_regions(water_regions, water_offset)
   local contiguous_regions = {}
   local all_water_region = Region3()
   for _, cube in pairs(water_regions) do
      all_water_region:add_cube(cube)
   end
   contiguous_regions = csg_lib.get_contiguous_regions(all_water_region)
   for _, region in pairs(contiguous_regions) do
      local bounds = region:get_bounds()
      local height = bounds.max.y - bounds.min.y - water_offset
      stonehearth.hydrology:create_water_body_with_region(region, height, true)  -- ACE: true to merge with adjacent water regions
   end
end

return AceLandmarkLib
