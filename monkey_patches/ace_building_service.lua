local Building = 'stonehearth:build2:building'

local BuildingService = require 'stonehearth.services.server.building.building_service'
local AceBuildingService = class()

function AceBuildingService:build(building_id, opt_ignored_entities, insert_craft_requests)
   return self:_get_building(building_id):get(Building):build(opt_ignored_entities or {}, insert_craft_requests)
end

function AceBuildingService:build_command(session, response, building_id, zero_point, insert_craft_requests)
   local job_status = self:build(building_id, nil, insert_craft_requests)
   response:resolve(job_status)
end

AceBuildingService._ace_old_blow_up_building = BuildingService.blow_up_building
function AceBuildingService:blow_up_building(building_id, player_id)
   local player_jobs_controller = stonehearth.job:get_jobs_controller(player_id)
   player_jobs_controller:remove_craft_orders_for_building(building_id)

   return self:_ace_old_blow_up_building(building_id, player_id)
end

return AceBuildingService