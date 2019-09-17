local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('build_well')

local build_well = {}

function build_well.on_initialize(entity)
   local transform_comp = entity:get_component('stonehearth_ace:transform')
   if transform_comp then
      local multiplier
      local min_volume = 100   -- don't consider water entities with very low volume
      local max_distance = 100

      -- find the closest water entity (as the neutrino flies) and use that distance as the multiplier
      local distance = max_distance
      local location = radiant.entities.get_world_grid_location(entity)
      local water_entities = stonehearth.hydrology:get_water_bodies()
      for _, water in pairs(water_entities) do
         local water_comp = water:get_component('stonehearth:water')
         if water_comp:get_volume() >= min_volume then
            distance = math.min(distance, radiant.entities.distance_between(entity, water))
         end
      end
      
      if distance < max_distance then
         multiplier = math.max(1, math.ceil(distance / 10))
      else
         multiplier = 20
      end

      local options = transform_comp:get_transform_options()
      transform_comp:add_option_overrides({
         transforming_worker_effect_times = options.transforming_worker_effect_times and options.transforming_worker_effect_times * multiplier,
         transforming_effect_duration = options.transforming_effect_duration and options.transforming_effect_duration * multiplier
      })
   end
end

return build_well