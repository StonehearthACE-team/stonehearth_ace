local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local HydrologyService = require 'stonehearth.services.server.hydrology.hydrology_service'
local AceHydrologyService = class()

local log = radiant.log.create_logger('hydrology')

AceHydrologyService._ace_old__create_tick_timer = HydrologyService._create_tick_timer
function AceHydrologyService:_create_tick_timer()
   self:_ace_old__create_tick_timer()

   -- make sure the ACE water signal service is up and running (mainly a fix for stupid microworlds)
   stonehearth_ace.water_signal:start()
end

-- Optimized path to create a water body that is already filled.
-- Does not check that region is contained by a watertight boundary.
-- Know what you are doing before calling this.
-- ACE: merge_adjacent option for landmark placement: check for water entities that would connect to this region; after creation, merge them
function HydrologyService:create_water_body_with_region(region, height, merge_adjacent)
   assert(not region:empty())

   local water_entities = {}
   if merge_adjacent then
      local water_bodies = self._sv._water_bodies
      local expanded_region = csg_lib.get_non_diagonal_xyz_inflated_region(region)
      local entities = radiant.terrain.get_entities_in_region(expanded_region)
      
      for id, entity in pairs(entities) do
         local water_component = entity:get_component('stonehearth:water')
         if water_component and water_bodies[id] then
            table.insert(water_entities, entity)
         end
      end
   end

   local boxed_region = _radiant.sim.alloc_region3()
   local location = self:select_origin_for_region(region)

   boxed_region:modify(function(cursor)
         cursor:copy_region(region)
         cursor:translate(-location)
      end)

   local water_entity = self:_create_water_body_internal(location, boxed_region, height)

   if merge_adjacent then
      log:debug('debug: merging water bodies %s with %s', radiant.util.table_tostring(water_entities), water_entity)
      for _, adjacent_water in ipairs(water_entities) do
         water_entity = self:merge_water_bodies(water_entity, adjacent_water, true)
      end
   end

   return water_entity
end

return AceHydrologyService