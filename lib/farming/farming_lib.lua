local farming_lib = {}

farming_lib.LOCATION_TYPES = {
   EMPTY = 0,
   FURROW = 1,
   CROP = 2
}

farming_lib.DEFAULT_PATTERN = {{2}, {1}}

function farming_lib.get_location_type(pattern, x, y)
   local row = pattern[1 + (x - 1) % #pattern]
   local value = row[1 + (y - 1) % #row]
   return value
end

function farming_lib.get_crop_coords(size_x, size_y, rotation, x, y)
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

return farming_lib