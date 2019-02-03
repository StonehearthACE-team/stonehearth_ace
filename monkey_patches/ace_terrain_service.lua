local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local validator = radiant.validator
local log = radiant.log.create_logger('terrain')

local CEILING_RAY = Point3(0, 15, 0)
local SUNRAY_DISTANCE = 100

AceTerrainService = class()

function AceTerrainService:get_sunlight_amount(location, distance)
   -- check straight above and at several east-west (x+ to x-) angles to determine amount of sunlight
   distance = distance or SUNRAY_DISTANCE
   
   local num_vis = 0
   for i = 1, 5 do
      local x, y = self:_get_unit_sides_from_angle(i / 6)
      local ray = Point3(x, y, 0) * distance

      local target = location + ray
      local end_point = _physics:shoot_ray(location, target, true, 0)
      if not radiant.terrain.is_blocked(end_point) then
         num_vis = num_vis + 1
      end
   end
   
   return num_vis / 5
end

function AceTerrainService:_get_unit_sides_from_angle(pi_coeff)
   local angle = pi_coeff * math.pi
   return math.cos(angle), math.sin(angle)
end

function AceTerrainService:is_sheltered(location, height)
   local ray = CEILING_RAY
   if height then
      ray = Point3(0, height, 0)
   end
   local target = location + ray

   -- Use RaycastLib.shoot_ray_filtered to shoot through objects we should ignore
   -- Not using it by default because it can be much slower
   local end_point = _physics:shoot_ray(location, target, true, 0)

   if radiant.terrain.is_blocked(end_point) then
      return true
   end

   -- The code below allows roofs to provide shelter to adjacent locations below.
   -- We're doing this so that Rayya's Children's building templates provide shelter.

   -- adjacent locations must be unblocked and have a blocked location above them
   -- (standing next to a wall should not be sheltered)
   for _, direction in ipairs(csg_lib.XZ_DIRECTIONS) do
      local source = location + direction
      local target = source + ray

      -- end_point will be nil of source is blocked
      end_point = _physics:shoot_ray(source, target, true, 0)
      if end_point and end_point ~= source then
         if radiant.terrain.is_blocked(end_point) then
            return true
         end
      end
   end

   return false
end

return AceTerrainService
