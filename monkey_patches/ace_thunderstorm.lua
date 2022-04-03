local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local AceThunderstormWeather = class()

local LIGHTNING_INTERVAL = '15m+30m'
local LIGHTNING_EFFECTS = {
   'stonehearth:effects:lightning_effect',
   'stonehearth:effects:lightning_effect2'
}
local LIGHTNING_GROUND_EFFECT = 'stonehearth:effects:lightning_impact_ground'
local LIGHTNING_TREE_EFFECT = 'stonehearth:effects:lightning_impact_tree'
local LIGHTNING_DAMAGE = 30
local LIGHTNING_TARGETS_SET = WeightedSet(rng)
LIGHTNING_TARGETS_SET:add('SPOT', 25)
LIGHTNING_TARGETS_SET:add('CITIZEN', 1)
local TREE_SEARCH_RADIUS = 3

function AceThunderstormWeather:_spawn_lightning()
   local effect = LIGHTNING_EFFECTS[rng:get_int(1, #LIGHTNING_EFFECTS)]
   local target = LIGHTNING_TARGETS_SET:choose_random()
   if target == 'CITIZEN' and stonehearth.game_creation:get_game_mode() ~= 'stonehearth:game_mode:peaceful' then
      local citizen = self:_select_random_player_character(effect)
      if citizen then
         local location = radiant.entities.get_world_grid_location(citizen)
         if location and not stonehearth.terrain:is_sheltered(location) then
            radiant.effects.run_effect(citizen, effect)
            radiant.entities.modify_health(citizen, -LIGHTNING_DAMAGE)
            radiant.entities.add_buff(citizen, 'stonehearth:buffs:weather:hit_by_lightning')
         end
      end
   elseif target == 'SPOT' then
      -- Choose a point to hit.
      local terrain_bounds = stonehearth.terrain:get_bounds()
      local x = rng:get_int(terrain_bounds.min.x, terrain_bounds.max.x)
      local z = rng:get_int(terrain_bounds.min.z, terrain_bounds.max.z)

      -- Find a tree to hit near our chosen point.
      local tree
      local search_cube = Cube3(Point3(x - TREE_SEARCH_RADIUS, terrain_bounds.min.y, z - TREE_SEARCH_RADIUS),
                                Point3(x + TREE_SEARCH_RADIUS, terrain_bounds.max.y, z + TREE_SEARCH_RADIUS))
      for _, item in pairs(radiant.terrain.get_entities_in_cube(search_cube)) do
         local catalog_data = stonehearth.catalog:get_catalog_data(item:get_uri()) or {}
         if item:get_component('stonehearth:resource_node') and catalog_data.category == 'plants' then
            tree = item
            break
         end
      end

      if tree then
         local location = radiant.entities.get_world_grid_location(tree)
         self:_spawn_effect_at(location, effect)
         self:_spawn_effect_at(location, LIGHTNING_TREE_EFFECT)
         -- ACE Changes start here; we don't want trees to drop their resources anymore. We'll drop some charcoal now, just for fun!
         if tree:is_valid() then
            radiant.entities.destroy_entity(tree)
            local charcoal_amount = rng:get_int(1,4)
            while charcoal_amount ~= 0 do
               local charcoal = radiant.entities.create_entity('stonehearth_ace:resources:coal:piece_of_charcoal')
               local charcoal_location = radiant.terrain.find_placement_point(location, 0, 3)
               radiant.terrain.place_entity(charcoal, charcoal_location)
               charcoal_amount = charcoal_amount - 1
            end
         end
         -- ACE Changes end here
      else
         local center = Point3(x, terrain_bounds.max.y, z)
         local target = Point3(x, terrain_bounds.min.y, z)
         local ground_point = _physics:shoot_ray(center, target, true, 0)

         -- Don't hit water.
         local search_cube = Cube3(ground_point - Point3(1, 2, 1),
                                   ground_point + Point3(1, 2, 1))
         local is_in_water = next(radiant.terrain.get_entities_in_cube(search_cube, function(e)
               return e:get_component('stonehearth:water') ~= nil
            end)) ~= nil
         if not is_in_water then
            ground_point.y = ground_point.y + 1  -- On top of the terain voxel.
            self:_spawn_effect_at(ground_point, effect)
            self:_spawn_effect_at(ground_point, LIGHTNING_GROUND_EFFECT)
         end
      end
   end
   self._sv._lightning_timer = stonehearth.calendar:set_persistent_timer('thunderstorm ligtning', LIGHTNING_INTERVAL, radiant.bind(self, '_spawn_lightning'))
end

return AceThunderstormWeather
