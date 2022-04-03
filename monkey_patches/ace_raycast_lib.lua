local RaycastLib = require 'stonehearth.ai.lib.raycast_lib'
local AceRaycastLib = class()

function AceRaycastLib.is_sight_blocked(source_point, destination_point, ignore_entity_fn)
   local result = RaycastLib.shoot_ray_filtered(source_point, destination_point, function(location)
         if not _physics:is_blocked(location, 0) then
            return false
         end
      
         local entities = radiant.terrain.get_entities_at_point(location)
      
         for id, entity in pairs(entities) do
            -- check for terrain
            if id == radiant._root_entity_id then
               return true
            end
            -- check for entities that aren't part of the ignore function
            if ignore_entity_fn and not ignore_entity_fn(entity) then
               return true
            end
         end
         
         return false
      end)

   return not result or result:to_closest_int() ~= destination_point:to_closest_int()
end

return AceRaycastLib
