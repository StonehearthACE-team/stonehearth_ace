--[[
   vines are complicated enough as cubic entities, we're going to assume that's the only shape they can be
   if someone wants another shape, they'll just have to mod it themselves
   also assume the vine is only 1x1x1 because otherwise it significantly increases the complexity of neighbor checks
   also assume the model is centered at 0.5, 0.5
]]
local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local RegionCollisionType = _radiant.om.RegionCollisionShape
local rng = _radiant.math.get_default_rng()

local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local ConnectionUtils = require 'lib.connection.connection_utils'
local log = radiant.log.create_logger('vine_component')

local VineComponent = class()

local _region = Region3(Cube3(Point3.zero, Point3.one))
local _directions = {
   ['x-'] = Point3(-1, 0, 0),
   ['x+'] = Point3(1, 0, 0),
   ['z-'] = Point3(0, 0, -1),
   ['z+'] = Point3(0, 0, 1),
   ['y-'] = Point3(0, -1, 0),
   ['y+'] = Point3(0, 1, 0)
}
local _opposite_direction = {
   ['x-'] = 'x+',
   ['x+'] = 'x-',
   ['z-'] = 'z+',
   ['z+'] = 'z-',
   ['y-'] = 'y+',
   ['y+'] = 'y-'
}
local STRUCTURE_URI = 'stonehearth:build2:entities:structure'
local FIXTURE_URI = 'stonehearth:build2:entities:fixture_blueprint'
local IGNORE_GROWTH_ATTEMPTS = 10

function VineComponent:initialize()
   self._current_season = nil
   
   if not self._sv.render_directions then
      self._sv.render_directions = {}
   end

   if not self._sv.render_options or not self._sv.render_models then
      local json = radiant.entities.get_json(self)
      local json_options = json.render_options or {}

      local options = {faces = {}, seasonal_model_switcher = json_options.seasonal_model_switcher}
      local models = {}
      local faces = {'bottom', 'top', 'side'}

      for _, face in ipairs(faces) do
         local j_o = json_options[face]
         if j_o then
            options.faces[face] = {
               scale = j_o.scale or 0.1,
               origin = radiant.util.to_point3(j_o.origin) or Point3.zero
            }
            models[face] = {}
            for season, qbs in pairs(j_o.models) do
               models[face][season] = qbs[rng:get_int(1, #qbs)]
            end
         end
      end

      self._sv.render_options = options
      self._sv.render_models = models
   end
end

function VineComponent:create()
   if self._sv.render_options.seasonal_model_switcher then
      self._sv.switch_season_time = rng:get_real(0, 1)  -- Choose a point in the transition at which this instance switches.
   end
end

function VineComponent:activate()
   self._uri = self._entity:get_uri()
   self._ignore_growth_attempts = 0
   self._growth_data = stonehearth_ace.vine:get_growth_data(self._uri) or {}
   self._growth_roller = WeightedSet(rng)
   self._corner_roller = WeightedSet(rng)
   for dir, chance in pairs(self._growth_data.growth_directions or {}) do
      if chance <= 0 then
         self._growth_data.growth_directions[dir] = nil
      end
   end
   self._growth_data.spreads_on_ground = self._growth_data.spreads_on_ground ~= false
   self._growth_data.spreads_on_ceiling = self._growth_data.spreads_on_ceiling ~= false
   self._growth_data.spreads_on_wall = self._growth_data.spreads_on_wall ~= false

   self._connection_data = self._entity:get_component('stonehearth_ace:connection'):get_connections(self._uri)

   self._parent_trace = self._entity:add_component('mob'):trace_parent('vine entity added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
   :on_changed(function(parent_entity)
      self:_set_render_directions()
   end)
end

function VineComponent:post_activate()
   if self._sv.render_options.seasonal_model_switcher then
      self._transition_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:transition', self, self._update_season)
      self:_update_season(stonehearth.seasons:get_current_transition())
   else
      self:_update_models('default')
   end
end

function VineComponent:destroy()
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   if self._transition_listener then
      self._transition_listener:destroy()
      self._transition_listener = nil
   end
end

function VineComponent:_update_models(season)
   for position, seasons in pairs(self._sv.render_models) do
      self._sv.render_options.faces[position].model = seasons[season]
   end

   self.__saved_variables:mark_changed()
end

function VineComponent:_update_season(transition)
   if self._current_season == transition.to then
      return  -- Already switched.
   elseif transition.t < self._sv.switch_season_time then
      if not self._current_season then
         self._current_season = transition.from
      end
      return  -- Not yet.
   elseif stonehearth.calendar:is_daytime() and transition.t < 1 then
      return  -- Try to swap at night, as long as it's not the final transition.
   end
   
   self._current_season = transition.to
   
   local biome_uri = stonehearth.world_generation:get_biome_alias()
   local biomes = self._sv.render_options.seasonal_model_switcher
   local biome_seasons = biomes[biome_uri] or biomes['*']
   if not biome_seasons then
      return
   end

   local new_variant = biome_seasons[self._current_season]
   if new_variant then
      self:_update_models(new_variant)
   end
end

function VineComponent:get_render_directions()
   if not next(self._sv.render_directions) then
      self:_set_render_directions()
   end

   return self._sv.render_directions
end

-- determine what sides of the voxel the vine should be rendered on
function VineComponent:_set_render_directions()
   local neighbors = self:get_neighbors(true)
   --log:error('setting render directions from neighbors: %s', radiant.util.table_tostring(neighbors))
   local render_dirs = {}
   -- the vine should render anywhere it's alongside terrain and anywhere it's connecting to another vine
   for dir, neighbor in pairs(neighbors) do
      if self:_is_growth_dir_permitted(dir) then
         if neighbor.is_growable_surface then
            render_dirs[dir] = true
         elseif neighbor.vine and dir == 'y+' then
            -- if the vine is hanging down from above, make sure we render on the same side(s)
            -- it's okay that this is recursive because it's only recursive in a single direction: up
            local neighbor_render_dirs = neighbor.vine:get_component('stonehearth_ace:vine'):get_render_directions()

            for n_dir, _ in pairs(neighbor_render_dirs) do
               if n_dir ~= 'y+' and n_dir ~= 'y-' then
                  render_dirs[n_dir] = true
               end
            end
         end
      end
   end

   self._sv.render_directions = render_dirs
   self.__saved_variables:mark_changed()
end

function VineComponent:_is_growth_dir_permitted(dir)
   return (dir == 'y-' and self._growth_data.grows_on_ground) or
         (dir == 'y+' and self._growth_data.grows_on_ceiling) or
         (dir ~= 'y-' and dir ~= 'y+' and self._growth_data.grows_on_wall)
end

-- try to grow another vine of the same type in a random direction; returns the new entity if successful
function VineComponent:try_grow()
   local attempts = self._ignore_growth_attempts or 0
   if attempts > 0 then
      self._ignore_growth_attempts = attempts - 1
      return
   end

   local neighbors = self:get_neighbors(true)
   if not next(neighbors) then
      return
   end

   self._growth_roller:clear()
   for dir, chance in pairs(self._growth_data.growth_directions) do
      self._growth_roller:add(dir, chance)
   end

   local new_vine

   -- evaluate each direction as we try it so we're not doing extra processing
   while not self._growth_roller:is_empty() do
      local dir = self._growth_roller:choose_random()
      self._growth_roller:remove(dir)

      local point = _directions[dir]
      local neighbor = neighbors[dir]
      local dir_chance = self._growth_data.growth_directions
      if dir_chance and dir_chance[dir] and neighbor and not neighbor.blocked then
         -- we can consider this space for growth
         -- however, we only want to grow in specific ways:
         --    - along a terrain wall (or possibly structure) in four cardinal directions
         --    - along the ground (or possibly structure) in four cardinal directions (but consider all six because of orientation)
         --    - along the ceiling (or possibly structure) in four cardinal directions
         --    - downward from a hanging vine
         -- so wherever we want to grow should share at least one horizontal growable surface neighbor direction
         -- or be downward growth with grows_hanging is true
         
         local add_dir = false
         local add_location = neighbor.location

         if dir == 'y-' and self._growth_data.grows_hanging then
            add_dir = true
         else
            local new_neighbors = self:_eval_neighbors_at(add_location, 0)

            if dir ~= 'y-' and dir ~= 'y+' and self._growth_data.grows_on_ground and self._growth_data.spreads_on_ground
                  and neighbors['y-'] and neighbors['y-'].is_growable_surface
                  and new_neighbors['y-'] and new_neighbors['y-'].is_growable_surface then
               add_dir = true
            elseif dir ~= 'y-' and dir ~= 'y+' and self._growth_data.grows_on_ceiling and self._growth_data.spreads_on_ceiling
                  and neighbors['y+'] and neighbors['y+'].is_growable_surface
                  and new_neighbors['y+'] and new_neighbors['y+'].is_growable_surface then
               add_dir = true
            elseif self._growth_data.grows_on_wall and self._growth_data.spreads_on_wall then
               -- make sure the new position has a wall it'll be growing on
               if (new_neighbors['x-'] and new_neighbors['x-'].is_growable_surface) or 
                     (new_neighbors['x+'] and new_neighbors['x+'].is_growable_surface) or 
                     (new_neighbors['z-'] and new_neighbors['z-'].is_growable_surface) or 
                     (new_neighbors['z+'] and new_neighbors['z+'].is_growable_surface) then
                  for grow_dir, _ in pairs(_directions) do
                     if neighbors[grow_dir] and neighbors[grow_dir].is_growable_surface and 
                           new_neighbors[grow_dir] and new_neighbors[grow_dir].is_growable_surface then
                        add_dir = true
                        break
                     end
                  end
               end
            end

            -- if we aren't already adding in this direction (and it's not blocked), consider growing around a corner in this direction
            if not add_dir then
               self._corner_roller:clear()
               for grow_dir, grow_chance in pairs(self._growth_data.growth_directions) do
                  -- don't check the same (or opposite) direction, only orthogonally
                  if string.sub(dir, 1, 1) ~= string.sub(grow_dir, 1, 1) then
                     if not new_neighbors[grow_dir].blocked and neighbors[grow_dir].is_growable_surface and
                           (self:_is_growth_dir_permitted(_opposite_direction[dir]) or (grow_dir == 'y-' and self._growth_data.grows_hanging)) then
                        self._corner_roller:add(add_location + _directions[grow_dir], grow_chance)
                     end
                  end
               end
               if not self._corner_roller:is_empty() then
                  add_dir = true
                  add_location = self._corner_roller:choose_random()
               end
            end
         end

         if add_dir then
            --log:spam('adding growth dir chance for %s %s (%s)', self._entity, dir, dir_chance[dir])
            new_vine = radiant.entities.create_entity(self._uri, { owner = self._entity:get_player_id(), ignore_gravity = true })
            radiant.terrain.place_entity_at_exact_location(new_vine, add_location, {force_iconic = false})
            break
         end
      end
   end

   if self._growth_roller:is_empty() then
      -- if we explored all growth options, ignore the next X growth attempts on this entity
      self._ignore_growth_attempts = IGNORE_GROWTH_ATTEMPTS
   end

   return new_vine
end

function VineComponent:get_neighbors(force_eval)
   force_eval = force_eval or not self._neighbors
   if force_eval then
      self:_eval_neighbors()
   end

   return self._neighbors
end

function VineComponent:_eval_neighbors()
   local location = radiant.entities.get_world_grid_location(self._entity)

   if location then
      local facing = radiant.entities.get_facing(self._entity)
      self._neighbors = self:_eval_neighbors_at(location, facing)
   else
      self._neighbors = {}
   end
end

function VineComponent:_eval_neighbors_at(location, facing)
   local neighbors = {}
   
   -- check in each direction
   for dir, point in pairs(_directions) do
      local neighbor = {}

      neighbor.location = location + point --+ radiant.math.rotate_about_y_axis(point, facing)
      neighbor.region = _region:translated(neighbor.location)

      -- first check if it's terrain
      local tag = radiant.terrain.get_block_tag_at(neighbor.location)
      neighbor.is_growable_surface = tag and tag ~= 0

      if neighbor.is_growable_surface then
         neighbor.blocked = true
      else
         -- if it's not terrain (i.e., it's null/air), check if any entities there are vines or solid
         for _, entity in pairs(radiant.terrain.get_entities_in_region(neighbor.region)) do
            if entity:get_uri() == self._uri then
               neighbor.vine = entity
               neighbor.blocked = true
               break
            elseif entity:get_uri() == STRUCTURE_URI then
               if self._growth_data.grows_on_structure then
                  neighbor.is_growable_surface = true
               end
               neighbor.blocked = true
               break
            elseif entity:get_uri() == FIXTURE_URI then
               neighbor.blocked = true
               break
            else
               local collision = entity:get_component('region_collision_shape')
               local type = collision and collision:get_region_collision_type()
               if type == RegionCollisionType.SOLID or type == RegionCollisionType.PLATFORM then
                  neighbor.blocked = true
               end
            end
         end
      end

      neighbors[dir] = neighbor
   end

   return neighbors
end

return VineComponent
