local log = radiant.log.create_logger('world_generation')

local AceHabitatManager = class()

local habitat_types = {
   none      = true,
   occupied  = true,
   plains    = true,
   foothills = true,
   mountains = true,
   forest    = true,
   water     = true
}

function AceHabitatManager.is_valid_habitat_type(habitat_type)
   return habitat_types[habitat_type]
end

-- This is likely to change
function AceHabitatManager:_get_habitat_type(terrain_type, feature_name)
   if terrain_type == 'mountains' then
      return 'mountains'
   end
   if self._landscaper:is_forest_feature(feature_name) then
      return 'forest'
   end
   if self._landscaper:is_water_feature(feature_name) then
      return 'water'
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
