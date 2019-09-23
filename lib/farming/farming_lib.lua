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

return farming_lib