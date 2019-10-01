local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local validator = radiant.validator
local log = radiant.log.create_logger('terrain')

local CEILING_RAY = Point3(0, 15, 0)
local SKYRAY_DISTANCE = 100
local _SINE = {}
local _COSINE = {}

local _get_sine = function(pi_coeff)
   local sine = _SINE[pi_coeff]
   if not sine then
      local angle = pi_coeff * math.pi
      sine = math.sin(angle)
      _SINE[pi_coeff] = sine
   end
   return sine
end

local _get_cosine = function(pi_coeff)
   local cosine = _COSINE[pi_coeff]
   if not cosine then
      local angle = pi_coeff * math.pi
      cosine = math.cos(angle)
      _COSINE[pi_coeff] = cosine
   end
   return cosine
end

AceTerrainService = class()

function AceTerrainService:get_sky_visibility(location, distance)
   -- check straight above and at several east-west (x+ to x-) angles to determine amount of sunlight
   distance = distance or SKYRAY_DISTANCE
   
   local total_weight = 0
   local vis_weight = 0
   local num_angles = stonehearth.constants.terrain.NUM_SUNLIGHT_CHECK_ANGLES
   for i = 1, num_angles - 1 do
      local x = _get_cosine(i / num_angles)
      local y = _get_sine(i / num_angles)
      local ray = Point3(x, y, 0) * distance

      local target = location + ray
      local end_point = _physics:shoot_ray(location, target, true, 0)
      if not radiant.terrain.is_blocked(end_point) then
         vis_weight = vis_weight + y
      end
      total_weight = total_weight + y
   end
   
   return vis_weight / total_weight
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
