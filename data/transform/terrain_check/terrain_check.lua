local Point3 = _radiant.csg.Point3

local terrain_check = {}

function terrain_check.meets_commmand_requirements(entity, requirements)
   local location = radiant.entities.get_world_grid_location(entity)

   if location then
      local terrain_point = radiant.terrain.get_point_on_terrain(location) - Point3.unit_y
      local block_kind = radiant.terrain.get_block_kind_at(terrain_point)
      
      if requirements.allowed_terrain then
         if not requirements.allowed_terrain[block_kind] then
            return false
         end
      end

      if requirements.disallowed_terrain then
         if requirements.disallowed_terrain[block_kind] then
            return false
         end
      end

      return true
   end

   return false
end

return terrain_check
