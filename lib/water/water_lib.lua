local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local water_lib = {}

function water_lib.get_water_in_front_of_entity(entity)
   local location = radiant.entities.get_world_grid_location(entity)
   if location then
      return water_lib.get_water_below_cliff(location, radiant.entities.get_facing(entity))
   end
end

function water_lib.get_water_below_cliff(land_point, pref_dir, allow_rotation)
   -- try to find water below the cliff, starting in the preferred direction and checking all other directions if necessary and allowed
   local rot = pref_dir or 0
   for i = 0, allow_rotation and 3 or 0 do
      local pt = Point3(0, 0, -1):rotated(rot)
      local origin = land_point + pt
      local water = water_lib._get_water_below(origin)
      if water then
         return water, origin, rot
      end
      rot = (rot + 90) % 360
   end
end

function water_lib._get_water_below(air_point)
   local ground_point = radiant.terrain.get_point_on_terrain(air_point)
   local entities_present = radiant.terrain.get_entities_at_point(ground_point)

   for id, entity in pairs(entities_present) do
      local water_component = entity:get_component('stonehearth:water')
      if water_component then
         return entity
      end
   end
end

function water_lib.get_contiguous_water_subregion(water, origin, square_radius)
   local water_comp = water:get_component('stonehearth:water')
   if not water_comp then
      return
   end

   local location = radiant.entities.get_world_grid_location(water)
   local region = water_comp.get_region and water_comp:get_region() or water_comp:get_data().region
   if location and region then
      return water_lib.get_contiguous_subregion(region:get():translated(location), origin, square_radius)
   end
end

-- get a partial contiguous region of a region centered on an origin
function water_lib.get_contiguous_subregion(region, origin, square_radius)
   local bounds = region:get_bounds()
   local clipper = Region3(Cube3(Point3(origin.x - square_radius, bounds.min.y, origin.z - square_radius),
                                 Point3(origin.x + square_radius, bounds.max.y, origin.z + square_radius)))
   local intersection = region:intersect_region(clipper)

   -- we only want a single contiguous region from the origin point
   local contained_origin = radiant.terrain.get_point_on_terrain(origin)
   local regions = csg_lib.get_contiguous_regions(intersection)
   for _, r in ipairs(regions) do
      if r:contains(contained_origin) then
         return r
      end
   end
end

return water_lib
