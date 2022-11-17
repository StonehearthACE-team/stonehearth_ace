local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()
local _standable_proxy

local log = radiant.log.create_logger('radiant_terrain')

local AceTerrain = {}

function AceTerrain.get_standable_proxy()
   if not _standable_proxy then
      _standable_proxy = radiant.entities.create_entity('stonehearth:object:transient')
      _standable_proxy:add_component('mob')
      local rcs = _standable_proxy:add_component('region_collision_shape')
      local boxed_region = radiant.alloc_region3()
      boxed_region:modify(function(cursor)
            cursor:copy_region(Region3(Cube3(Point3(0, 0, 0), Point3(1, 3, 1))))
         end)
      rcs:set_region(boxed_region)
   end
   return _standable_proxy
end

-- ACE: allow require_reachable to specify an entity or location for the point to be reachable from
-- only finds points at the same elevation as origin
function AceTerrain.find_placement_point(origin, min_radius, max_radius, entity, step_size, require_reachable)
   -- pick a random start location
   local x = rng:get_int(-max_radius, max_radius)
   local z = rng:get_int(-max_radius, max_radius)

   local s = 1
   if step_size and step_size > 0 then
      s = step_size
   end

   -- move to the next point in the box defined by max_radius
   local function inc(x, z)
      x = x + s
      if x > max_radius then
         x, z = -max_radius, z + s
      end
      if z > max_radius then
         z = -max_radius
      end
      return x, z
   end

   -- make sure x, z is inside the donut described by min_radius and max_radius
   local function valid(x, z)
      -- if z inside min_radius
      if z > -min_radius and z < min_radius then
         -- return whether x is on or outside min_radius
         return x <= -min_radius or x >= min_radius
      end
      return true
   end

   -- run through all the points in the box.  for the ones that are in the donut,
   -- see if they're both capable holding an item and not-occupied.  if we loop
   -- all the way around and still can't find something, just use the starting
   -- point as the placement point.
   local pt
   local found = false
   local diameter = 2*max_radius + 1 -- add 1 to include origin square
   local fallback_point = nil
   local num_tries = 0
   local points_per_dimension = (diameter - 1)/s + 1
   local num_points = math.floor(points_per_dimension * points_per_dimension)
   local standable_proxy
   local require_reachable_entity
   if require_reachable then
      standable_proxy = radiant.terrain.get_standable_proxy()
      if radiant.entities.is_entity(require_reachable) then
         require_reachable_entity = require_reachable
      else
         require_reachable_entity = entity
      end
   end

   local perf_timer = radiant.create_perf_timer()
   perf_timer:start()

   for i=1, num_points do
      if valid(x, z) then
         pt = origin + Point3(x, 0, z)
         local is_standable = false
         local is_reachable = true
         if entity then
            is_standable = _physics:is_standable(entity, pt)
         else
            is_standable = _physics:is_standable(pt, 0)
         end
         if standable_proxy then
            is_standable = is_standable and _physics:is_standable(standable_proxy, pt)
         end
         if is_standable then
            if require_reachable_entity then
               is_reachable = _radiant.sim.topology.are_connected(require_reachable_entity, pt)
            end
            if is_reachable then
               if not _physics:is_occupied(pt, 0) then
                  found = true
                  break
               else
                  if not fallback_point then
                     fallback_point = pt
                  end
               end
            end
         end
      end
      num_tries = num_tries + 1
      x, z = inc(x, z)
   end

   if not found then
      -- fallback to a standable point, but still indicate not found
      pt = fallback_point or origin
   end

   local del = perf_timer:stop()
   if del > 50 then
      local error_str = string.format('Terrain.find_placement_point took %dms to complete. Num tries: %d. Found: %s', del, num_tries, tostring(found))
      radiant.log.write('terrain', 0, error_str)
   end

   return pt, found
end

return AceTerrain
