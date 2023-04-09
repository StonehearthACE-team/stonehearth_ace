local Point3 = _radiant.csg.Point3
local pattern_lib = require 'stonehearth_ace.lib.pattern.pattern_lib'

local PatternCalculator = class()

-- pattern, min/max sizes, and border are all static
-- actual size and rotation are dynamic for region selector, so make those set-able
function PatternCalculator:__init(pattern, max_size, border)
   self._pattern = pattern
   self._max_size = max_size
   self._border = border or 0
   self._max_interior_size = self._max_size - self._border * 2
   self:set_size(self._max_size, self._max_size)
   self:set_rotation(0)
end

function PatternCalculator:set_size(size_x, size_y)
   self._size_x = size_x
   self._size_y = size_y
   self._interior_size_x = self._size_x - self._border * 2
   self._interior_size_y = self._size_y - self._border * 2
   return self
end

function PatternCalculator:set_rotation(rotation)
   self._rotation = rotation
   return self
end

function PatternCalculator:get_pattern_coords(x, y)
   local xb, yb = x - self._border, y - self._border
   if xb < 1 or yb < 1 or xb > self._interior_size_x or yb > self._interior_size_y then
      return
   end

   return self:get_internal_pattern_coords(xb, yb)
end

function PatternCalculator:get_internal_pattern_coords(x, y)
   return pattern_lib.get_pattern_coords(self._interior_size_x, self._interior_size_y, self._rotation, x, y)
end

function PatternCalculator:get_location_type(x, y)
   local xb, yb = x - self._border, y - self._border
   if xb < 1 or yb < 1 or xb > self._interior_size_x or yb > self._interior_size_y then
      return
   end

   local rot_x, rot_y = self:get_internal_pattern_coords(xb, yb)
   return self:get_internal_location_type(rot_x, rot_y)
end

function PatternCalculator:get_internal_location_type(x, y)
   return pattern_lib.get_location_type(self._pattern, x, y)
end

function PatternCalculator:get_locations_by_type()
   local locations = {}

   for x = 1, self._interior_size_x do
      for y = 1, self._interior_size_y do
         local rot_x, rot_y = self:get_internal_pattern_coords(x, y)
         local t = self:get_internal_location_type(rot_x, rot_y)
         if t then
            local t_l = locations[t]
            if not t_l then
               t_l = {}
               locations[t] = t_l
            end
            table.insert(t_l, Point3(rot_x + self._border - 1, 0, rot_y + self._border - 1))
         end
      end
   end

   return locations
end

return PatternCalculator
