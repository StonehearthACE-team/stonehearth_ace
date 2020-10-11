local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()

local AceRunInCircles = class()

local function _rotate(x, z, angle)
   if angle ==  90 then return -z,  x end
   if angle == -90 then return  z, -x end
   if angle ==   0 then return  x,  z end
   if angle == 180 then return -x, -z end
   assert(false)
end

local function _random_sign()
   return rng:get_int(0, 1)*2 - 1
end

local function _random_vector(size)
   -- randomize sign
   local v = Point3(_random_sign() * size, 0, 0)

   -- randomize axis
   if rng:get_int(0, 1) == 1 then
      v.x, v.z = v.z, v.x
   end

   return v
end

-- ACE: if the pet is out of the world, just exit early, no need to abort
function AceRunInCircles:run(ai, entity, args)
   local location = entity:add_component('mob'):get_world_grid_location()
   if not location then
      return
   end

   local randomize_circles = rng:get_real(0, 1) < self._random_circle_probability
   local v = _random_vector(self._circle_size)
   local angle = _random_sign() * 90

   for n=1, self._num_circles do
      -- traverse the four edges of the "circle"
      for i=1, 4 do
         location = location + v

         -- gotoward_location will suspend the thread between steps so we won't lock the thread
         ai:execute('stonehearth:go_toward_location', { destination = location })

         if i < 4 then
            v.x, v.z = _rotate(v.x, v.z, angle)
         end
      end

      if randomize_circles then
         -- pick a direction (-90, 0, 90) that doesn't backtrack for the next circle
         angle = rng:get_int(-1, 1) * 90
      end

      -- set the vector to the new direction
      v.x, v.z = _rotate(v.x, v.z, angle)

      if randomize_circles then
         -- pick a clockwise or counterclockwise circle
         angle = _random_sign() * 90
      end
   end
end

return AceRunInCircles
