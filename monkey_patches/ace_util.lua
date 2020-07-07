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

return ace_util
