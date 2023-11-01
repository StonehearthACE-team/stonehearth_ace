local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4
local ace_util = {}

function ace_util.to_region3(boxes)
   local has_cube = false
   local region = Region3()
   
   if boxes and type(boxes) == 'table' then
      for _, box in ipairs(boxes) do
         local cube = radiant.util.to_cube3(box)
         if cube then
            has_cube = true
            region:add_cube(cube)
         end
      end
   end

   return has_cube and region
end

function ace_util.to_color4(pt, a)
   return pt and ((pt.x and pt.y and pt.z and Color4(pt.x, pt.y, pt.z, a)) or (pt.r and pt.g and pt.b and Color4(pt.r, pt.g, pt.b, a))) or nil
end

function ace_util.get_rotations_table(json)
   local result = {}

   for _, rotation in pairs(json and json.rotations or {}) do
      local origin = radiant.util.to_point3(rotation.origin) or Point3.zero
      local offset = radiant.util.to_point3(rotation.offset) or Point3.zero
      local direction = radiant.util.to_point3(rotation.direction)
      -- the terminus, if not explicitly specified, needs to increase by 1 the non-direction dimensions of the origin
      local terminus = radiant.util.to_point3(rotation.terminus) or
         Point3(origin.x + (direction.x == 0 and 1 or 0), origin.y + (direction.y == 0 and 1 or 0), origin.z + (direction.z == 0 and 1 or 0))
      local min_length = rotation.min_length or json.min_length or 1
      local max_length = rotation.max_length or json.max_length or min_length
      local valid_lengths = rotation.valid_lengths or json.valid_lengths
      local matrix = rotation.matrix or json.matrix
      local material = rotation.material or json.material
      local scale = rotation.scale or json.scale
      local connector_region
      if rotation.connector_region then
         connector_region = Region3()
         connector_region:load(rotation.connector_region)
      end
      local connection_type = rotation.connection_type or json.connection_type

      if origin and direction and min_length then
         table.insert(result, {
            origin = origin,
            terminus = terminus,
            direction = direction,
            min_length = min_length,
            max_length = max_length,
            valid_lengths = valid_lengths,
            dimension = rotation.dimension,
            rotation = rotation.rotation,
            model = rotation.model,
            matrix = matrix,
            material = material,
            scale = scale,
            offset = offset,
            connection_type = connection_type,
            connector_id = rotation.connector_id,
            connector_region = connector_region,
         })
      end
   end

   return result
end

return ace_util
