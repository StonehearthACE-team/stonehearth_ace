local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('client_entities')

local ace_client_entities = {}

function ace_client_entities.get_facing(entity)
   if not entity or not entity:is_valid() then
      return nil
   end

   local mob = entity:get_component('mob')
   if not mob then
      return nil
   end

   local rotation = mob:get_rotation()
   if rotation.x ~= 0 or rotation.z ~= 0 then
      -- if it's rotated on x or z, mob:get_facing() will cause a c++ assert fail!
      -- so get the flat y rotation instead
      rotation.x = 0
      rotation.z = 0
      rotation:normalize()
      -- angle in radians = 2 * acos(q.w); multiply by 180 / pi to convert to degrees
      return 360 * math.acos(rotation.w) / math.pi
   else
      return mob:get_facing()
   end
end

-- Returns the (voxel, integer) grid location in front of the specified entity.
function ace_client_entities.get_grid_in_front(entity)
   local mob = entity:get_component('mob')
   local facing = radiant.math.round(radiant.entities.get_facing(entity) / 90) * 90
   local location = mob:get_world_grid_location()
   local offset = radiant.math.rotate_about_y_axis(-Point3.unit_z, facing):to_closest_int()
   return location + offset
end

function ace_client_entities.is_solid_location(location)
   local entities = radiant.terrain.get_entities_at_point(location)

   for _, entity in pairs(entities) do
      if radiant.entities.is_solid_entity(entity) then
         return true
      end
   end

   return false
end

return ace_client_entities
