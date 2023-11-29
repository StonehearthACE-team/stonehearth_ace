local fixture_utils = require 'stonehearth.lib.building.fixture_utils'

local AceDecorationTool = class()

function AceDecorationTool:_get_current_building_room_region()
   if not self._current_building_room_region then
      self._current_building_room_region = stonehearth.building:get_current_building_room_region()
   end
   return self._current_building_room_region
end

function AceDecorationTool:_calculate_stab_point(p)
   return fixture_utils.find_fixture_placement(p, self._widget, self._embedded, self._fence,
         self.local_bounds, self.bounds_origin, self._allow_ground, self._rotation, self._allow_walls, self:_get_current_building_room_region())
end

return AceDecorationTool
