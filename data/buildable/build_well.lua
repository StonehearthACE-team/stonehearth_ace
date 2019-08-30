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

      -- find the closest water entity (as the neutrino flies) and use that distance as the multiplier
      local location = radiant.entities.get_world_grid_location(entity)
      local water_entities = stonehearth.hydrology:get_water_bodies()
      local water_regions = {}
      for _, water in pairs(water_entities) do
         local water_comp = water:get_component('stonehearth:water')
         if water_comp:get_volume() >= min_volume then
            table.insert(water_regions, water_comp:get_region():get():translated(water_comp:get_location()))
         end
      end
      
      -- there doesn't seem to be an easy way to get the closest edge to a given point, so just do a for loop and keep expanding our check range
      if #water_regions > 0 then
         local cube = Cube3(location)
         for i = 10, 100, 10 do
            local exp_reg = Region3(cube:inflated(Point3(i, i, i)))
            for _, region in ipairs(water_regions) do
               if exp_reg:intersects_region(region) then
                  --log:debug('found water region %s at distance %s', region:get_bounds(), i)
                  multiplier = i / 10
                  break
               end
            end

            if multiplier then
               break
            end
         end
      end

      if not multiplier then
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