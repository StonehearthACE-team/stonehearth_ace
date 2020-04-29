local Point3 = _radiant.csg.Point3

local water_lib = {}

function water_lib.get_water_below_cliff(land_point, pref_dir)
   -- try to find water below the cliff, starting in the preferred direction and checking all other directions if necessary
   local rot = pref_dir or 0
   for i = 0, 3 do
      local pt = Point3(0, 0, -1):rotated(rot)
      local water = water_lib._get_water_below(land_point + pt)
      if water then
         return water, rot
      end
      rot = (rot + 90) % 360
   end
end

function water_lib._get_water_below(air_point)
   local ground_point = radiant.terrain.get_point_on_terrain(pt)
   local entities_present = radiant.terrain.get_entities_at_point(ground_point)

   for id, entity in pairs(entities_present) do
      local water_component = entity:get_component('stonehearth:water')
      if water_component then
         return entity
      end
   end
end

-- get a partial region of a [partial] water region centered on an origin
function water_lib.get_water_region(water, origin, ignore_region, min_width, min_volume, max_width, max_volume)
   local water_comp = water:get_component('stonehearth:water')
   if not water_comp then
      return
   end

   local region = Region3(water_comp:get_region():get())
   if ignore_region then
      region:subtract_region(ignore_region)
   end
   if region:empty() then
      return
   end

   local volume = region:get_area()
   if min_volume and volume < min_volume then
      return
   end

   -- if any remaining region is smaller than the minimum volume, just return the whole remainder
   if max_volume and min_volume and (volume - max_volume < min_volume) then
      return region
   end

   -- project the region onto a 2d plane to simplify process?
   local projection = region:project_onto_xz_plane()

   
end

return water_lib
