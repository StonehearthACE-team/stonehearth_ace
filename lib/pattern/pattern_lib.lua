local pattern_lib = {}

function pattern_lib.get_location_type(pattern, x, y)
   local row = pattern[1 + (x - 1) % #pattern]
   local value = row[1 + (y - 1) % #row]
   return value
end

function pattern_lib.get_pattern_coords(size_x, size_y, rotation, x, y)
   if rotation == 0 then
      return x, y
   elseif rotation == 1 then
      return y, size_x + 1 - x
   elseif rotation == 2 then
      return size_x + 1 - x, size_y + 1 - y
   elseif rotation == 3 then
      return size_y + 1 - y, x
   else
      -- and just in case rotation is invalid, return something safe
      return 1, 1
   end
end

return pattern_lib
