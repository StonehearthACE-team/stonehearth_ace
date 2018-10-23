local log = radiant.log.create_logger('world_generation')

local HabitatManager = require 'stonehearth.services.server.world_generation.habitat_manager'
local AceHabitatManager = class()

function AceHabitatManager:initialize()
   self._habitat_types = stonhearth.constants.world_generation.habitat_types
end

-- have to override this function to use our version of the habitat_types
-- also move away from local and make it import the list from constants json
function AceHabitatManager.is_valid_habitat_type(habitat_type)
   return self._habitat_types[habitat_type]
end

AceHabitatManager._old__get_habitat_type = HabitatManager._get_habitat_type
function AceHabitatManager:_get_habitat_type(terrain_type, feature_name)
   if self._landscaper:is_water_feature(feature_name) then
      return 'water'
   end
   return self:_old__get_habitat_type(terrain_type, feature_name)
end

return AceHabitatManager
