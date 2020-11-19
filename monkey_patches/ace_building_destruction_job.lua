local BuildingDestructionJob = require 'stonehearth.components.building2.building_destruction_job'
local AceBuildingDestructionJob = class()

local log = radiant.log.create_logger('build2.building_destruction_job')

AceBuildingDestructionJob._ace_old_start = BuildingDestructionJob.start
function AceBuildingDestructionJob:start()
   self:_ace_old_start()

   -- figure out what banked resource entities need to be dropped and create them
   local building_comp = self._building_entity:get_component('stonehearth:build2:building')
   local region = building_comp:get_envelope_entity():get_component('destination'):get_region():get()
   local bounds = region:get_bounds()
   local location = radiant.terrain.get_standable_point(bounds:get_centroid())
   local radius = math.ceil(math.min(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z) / 3)
   log:debug('%s dumping banked resources at %s within %s radius (bounds: %s)', self._building_entity, location, radius, bounds)

   local items = self:_create_banked_resource_entities(building_comp:get_banked_resources())
   building_comp:destroy_banked_resources()
   radiant.entities.output_spawned_items(items, location, 0, radius, nil, nil, nil, true)
end

function AceBuildingDestructionJob:_create_banked_resource_entities(banked_resources)
   local player_id = radiant.entities.get_player_id(self._building_entity)
   local items = {}
   
   for material, resource in pairs(banked_resources) do
      local num = resource.count
      if num > 0 then
         local resource_data = stonehearth.constants.resources[material]
         local res = resource_data and resource_data.default_resource

         if res then
            while num > 0 do
               local item = radiant.entities.create_entity(res, {owner = player_id})
               num = num - item:get_component('stonehearth:stacks'):get_stacks()
               items[item:get_id()] = item
            end
         end
      end
   end
   
   return items
end

return AceBuildingDestructionJob
