local BuildingService = require 'stonehearth.services.server.building.building_service'
local AceBuildingService = class()

AceBuildingService._ace_old_blow_up_building = BuildingService.blow_up_building
function AceBuildingService:blow_up_building(building_id, player_id)
   local player_jobs_controller = stonehearth.job:get_jobs_controller(player_id)
   player_jobs_controller:remove_craft_orders_for_building(building_id)

   return self:_ace_old_blow_up_building(building_id, player_id)
end

return AceBuildingService