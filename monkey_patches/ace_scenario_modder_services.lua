local PerturbationGrid = require 'stonehearth.services.server.world_generation.perturbation_grid'
local Point3 = _radiant.csg.Point3

local AceScenarioModderServices = class()

function AceScenarioModderServices:place_entity(uris, x, y, randomize_facing, options)
   if randomize_facing == nil then
      randomize_facing = true
   end

   x, y = self:_bounds_check(x, y)

   -- switch from lua height_map base 1 coordinates to c++ base 0 coordinates
   -- swtich from scenario coordinates to world coordinates
   local world_x, world_y = self:to_world_coordinates(x, y)

   local uri = uris[self.rng:get_int(1, #uris)]
   local entity = radiant.entities.create_entity(uri)
   local desired_location = radiant.terrain.get_point_on_terrain(Point3(world_x, 0, world_y))
   local actual_location = radiant.terrain.find_closest_standable_point_to(desired_location, 16, entity, true)  -- ignore_reachability
   radiant.terrain.place_entity(entity, actual_location, options)

   if randomize_facing then
      self:_set_random_facing(entity)
   end

   return entity
end

function AceScenarioModderServices:place_entity_cluster(uris, quantity, entity_footprint_length, randomize_facing, options)
   local entities = {}
   local rng = self.rng
   local size = self._properties.size
   local grid_spacing = self:_get_perturbation_grid_spacing(size.width, size.length, quantity)
   local grid = PerturbationGrid(size.width, size.length, grid_spacing, self.rng)
   local margin_size = math.floor(entity_footprint_length / 2)
   local num_cells_x, num_cells_y = grid:get_dimensions()
   local cells_left = num_cells_x * num_cells_y
   local num_selected = 0
   local x, y, probability, entity

   for j=1, num_cells_y do
      for i=1, num_cells_x do
         -- this algorithm guarantees that each cell has an equal probability of being selected
         probability = (quantity - num_selected) / cells_left

         if rng:get_real(0, 1) < probability then
            x, y = grid:get_perturbed_coordinates(i, j, margin_size)
            entity = self:place_entity(uris, x, y, randomize_facing, options)
            entities[entity:get_id()] = entity
            num_selected = num_selected + 1

            if num_selected == quantity then
               return entities
            end
         end
         cells_left = cells_left - 1
      end
   end

   return entities
end

return AceScenarioModderServices