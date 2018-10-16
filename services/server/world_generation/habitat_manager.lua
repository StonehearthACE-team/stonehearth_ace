local HabitatManager = require 'stonehearth.services.server.world_generation.habitat_manager'
AceHabitatManager = class()

local habitat_types = {
   none      = true,
   occupied  = true,
   plains    = true,
   foothills = true,
   mountains = true,
   water	 = true,
   forest    = true
}

function AceHabitatManager:_get_habitat_type(terrain_type, feature_name)
   if terrain_type == 'mountains' then
      return 'mountains'
   end
   if self._landscaper:is_water_feature(feature_name) then
      return 'water'
   end
   if self._landscaper:is_forest_feature(feature_name) then
      return 'forest'
   end
   if feature_name ~= nil then
      return 'occupied'
   end
   if terrain_type == 'plains' then
      return 'plains'
   end
   if terrain_type == 'foothills' then
      return 'foothills'
   end
   log:error('Unable to derive habitat_type')
   return 'none'
end

return AceHabitatManager