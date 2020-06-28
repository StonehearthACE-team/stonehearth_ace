local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
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

return ace_util
