local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local rng = _radiant.math.get_default_rng()

local AceFabricateChunkAdjacent = radiant.class()

local function get_build_rate(entity)
   local player_id = radiant.entities.get_player_id(entity)
   local tier = stonehearth.population:get_population(player_id):get_city_tier()

   if tier <= 1 then
      return stonehearth.constants.building.build_rate.TIER_1
   elseif tier == 2 then
      return stonehearth.constants.building.build_rate.TIER_2
   elseif tier >= 3 then
      return stonehearth.constants.building.build_rate.TIER_3
   end
   return 1
end

function AceFabricateChunkAdjacent:build_adjacent_to_current_block(ai, entity, args)
   assert(self._current_block ~= nil)

   local standing = radiant.entities.get_world_grid_location(entity)

   local job_component = entity:get_component('stonehearth:job')
   local num_times = get_build_rate(entity)

   -- these perks only exist in the unused architect job; don't both with them
   -- local material_conservation_chance = 0
   -- if job_component then
   --    if job_component:curr_job_has_perk('increased_construction_rate') then
   --       num_times = num_times + stonehearth.constants.building.INCREASED_CONSTRUCTION_RATE_ADDITIONAL_BLOCKS
   --    end

   --    if job_component:curr_job_has_perk('construction_material_conservation_1') then
   --       material_conservation_chance = 50
   --    end
   -- end

   local building_comp = self._chunk_c:get_owning_building():get_component('stonehearth:build2:building')

   local work_available = false
   repeat
      radiant.entities.turn_to_face(entity, self._current_block + self._origin)

      ai:execute('stonehearth:run_effect', { effect = 'work' })

      if not self._chunk:is_valid() then
         break
      end
      local num_blocks_added, work_available = self._chunk_c:fabricate_blocks(self._material, self._current_block, num_times)


      if num_blocks_added <= 0 then
         self._current_block = nil
         break
      end
      if self._has_material then
         building_comp:spend_banked_resource(self._material, num_blocks_added)
         if not building_comp:has_banked_resource(self._material) then
            self._current_block = nil
            break
         end
      end
   until not work_available
end

return AceFabricateChunkAdjacent