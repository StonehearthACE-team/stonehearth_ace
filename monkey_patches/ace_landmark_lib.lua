local Region3 = _radiant.csg.Region3
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local terrain_blocks = radiant.resources.load_json("stonehearth:terrain_blocks", true, false)

local AceLandmarkLib = {}

-- ACE: don't clip max y to the hard-coded 256 in the terrain component
-- Remove any part of region that is outside the allowed bounds of terrain or intersects with bedrock (tag of 100)
function AceLandmarkLib.intersect_with_terrain_bounds_and_remove_bedrock(region)
   -- Remove out of bounds areas
   local bounds = radiant.terrain.get_terrain_component():get_bounds()
   bounds.max.y = stonehearth.constants.terrain.MAX_Y_OVERRIDE
   region = region:intersect_cube(bounds)
   -- Remove bedrock areas
   local terrain_check_region = radiant.terrain.intersect_cube(region:get_bounds())
   for cube in terrain_check_region:each_cube() do
      if cube.tag and cube.tag == terrain_blocks.block_types.bedrock.tag then
         region:subtract_cube(cube)
      end
   end
   return region
end

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
