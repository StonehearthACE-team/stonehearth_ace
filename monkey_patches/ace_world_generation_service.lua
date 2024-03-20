local HeightMapRenderer = require 'stonehearth.services.server.world_generation.height_map_renderer'
local Timer = require 'stonehearth.services.server.world_generation.timer'
local Cube3 = _radiant.csg.Cube3
local log = radiant.log.create_logger('world_generation')

local WorldGenerationService = require 'stonehearth.services.server.world_generation.world_generation_service'
local AceWorldGenerationService = class()

AceWorldGenerationService._ace_old__setup_biome_data = WorldGenerationService._setup_biome_data
function AceWorldGenerationService:_setup_biome_data(biome_src)
   self:_ace_old__setup_biome_data(biome_src)

   self:_create_height_map_renderer()
end

function AceWorldGenerationService:_create_height_map_renderer()
   if self._biome_generation_data then
      self._height_map_renderer = HeightMapRenderer(self._biome_generation_data)
   end
end

function AceWorldGenerationService:get_height_map_renderer()
   return self._height_map_renderer
end

function AceWorldGenerationService:get_rock_terrain_tag_at_height(height)
   return self._height_map_renderer and self._height_map_renderer:get_rock_terrain_tag_at_height(height)
end

function AceWorldGenerationService:_add_water_bodies(regions)
   local biome_landscape_info = self._biome_generation_data:get_landscape_info()
   local biome_water_height_delta = biome_landscape_info and biome_landscape_info.water and biome_landscape_info.water.water_height_delta
   local water_height_delta = biome_water_height_delta or 1.5

   local seconds = Timer.measure(
      function()
         for _, terrain_region in pairs(regions) do
            terrain_region:force_optimize('add water bodies')

            local terrain_bounds = terrain_region:get_bounds()

            -- Water level is 1.5 blocks below terrain. (by default, can be changed in the biome json)
            -- Avoid filling to integer height so that we can avoid raise and lower layer spam.
            local height = terrain_bounds:get_size().y - water_height_delta

            local water_bounds = Cube3(terrain_bounds)
            water_bounds.max.y = water_bounds.max.y - math.floor(water_height_delta)

            local water_region = terrain_region:intersect_cube(water_bounds)
            stonehearth.hydrology:create_water_body_with_region(water_region, height, true)  -- ACE: true to merge with adjacent water regions
         end
      end
   )

   log:info('Add water bodies time: %.3fs', seconds)
end

return AceWorldGenerationService
