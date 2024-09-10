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

local get_block_tag_at = radiant.terrain.get_block_tag_at
local get_block_kind_from_tag = radiant.terrain.get_block_kind_from_tag
local get_entities_in_region = radiant.terrain.get_entities_in_region

local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local resources_lib = require 'stonehearth_ace.lib.resources.resources_lib'
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
local SPREAD_FN_DEFAULT = 'default'
local SPREAD_FN_HORIZONTAL_WALK = 'horizontal_walk'

function VineComponent:initialize()
   self._sv._growth_timer = nil
   self._current_season = nil
   
   if not self._sv.render_directions then
      self._sv.render_directions = {}
   end

   if self._sv.casts_shadows == nil then
      self._sv.casts_shadows = true
   end

   self._json = radiant.entities.get_json(self)
   self._json_options = radiant.deep_copy(self._json.render_options or {})

   self._uri = self._entity:get_uri()
   self._growth_data = self._json.growth_data or {}
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
   self._growth_data.terrain_types = self._growth_data.terrain_types or {['dirt'] = true, ['grass'] = true}
   self._spread_function = self._growth_data.spread_function or {}
   self._spread_function.type = self._spread_function.type or SPREAD_FN_DEFAULT
   if self._spread_function.type == SPREAD_FN_HORIZONTAL_WALK then
      self._spread_function.min_steps = math.max(1, self._spread_function.min_steps or 1)
      self._spread_function.max_steps = math.max(self._spread_function.min_steps, self._spread_function.max_steps or 1)
      self._spread_function.max_drop = self._spread_function.max_drop or 1
   end
end

function VineComponent:create()
   local options = {faces = {}, seasonal_model_switcher = self._json.seasonal_model_switcher and radiant.deep_copy(self._json.seasonal_model_switcher)}
   local models = {}
   local faces = {'bottom', 'top', 'side'}

   for _, face in ipairs(faces) do
      local j_o = self._json_options[face]
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
   self._sv._render_models = models
   if self._json_options.casts_shadows ~= nil then
      self._sv.casts_shadows = self._json_options.casts_shadows
   end

   if self._sv.render_options.seasonal_model_switcher then
      self._sv._switch_season_time = rng:get_real(0, 1)  -- Choose a point in the transition at which this instance switches.
   end
   -- instead of making all naturally-spawning vines not grow, just have them start with a lower num_growths_remaining
   -- since they always decrease it when growing, they should never take over the world
   local player_id = self._entity:get_player_id()
   self:set_num_growths_remaining(player_id == '' and (self._growth_data.natural_num_growths_remaining or 0))
   -- (otherwise, if there is a player_id, it'll set it to the normal starting value)
end

function VineComponent:restore()
   if not self._sv.num_growths_remaining then
      self:set_num_growths_remaining(self._growth_data.natural_num_growths_remaining or 0)
   end
end

function VineComponent:activate()
   local entity_forms = self._entity:get_component('stonehearth:entity_forms')
   if entity_forms then
      -- If we have an entity forms component, wait until we are actually in the world before starting the growth timer
      self._added_to_world_trace = radiant.events.listen_once(self._entity, 'stonehearth:on_added_to_world', function()
            self:_start()
            self._added_to_world_trace = nil
         end)
   else
      self:_start()
   end

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
   if self._added_to_world_trace then
      self._added_to_world_trace:destroy()
      self._added_to_world_trace = nil
   end
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   if self._transition_listener then
      self._transition_listener:destroy()
      self._transition_listener = nil
   end

   self:_stop_growth_timer()

   if self._sv.vine_group and self._entity:is_valid() then
      self._sv.vine_group:remove_vine(self._entity:get_id())
   end
end

function VineComponent:_stop_growth_timer()
   if self._sv._growth_timer then
      self._sv._growth_timer:destroy()
      self._sv._growth_timer = nil
   end

   --self.__saved_variables:mark_changed()
end

function VineComponent:_start_growth_timer()
   self:_stop_growth_timer()
   
   if self._sv.num_growths_remaining > 0 then
      local duration = self:_get_growth_period(self._sv.num_growths_remaining)
      if duration > 0 then
         self._sv._growth_timer = stonehearth.calendar:set_persistent_timer("VineComponent try_grow", duration, radiant.bind(self, 'try_grow'))
         --self.__saved_variables:mark_changed()
      end
   end
end

function VineComponent:_start()
   if not self._sv._growth_timer or not self._sv._growth_timer.bind then
      self:_start_growth_timer()
   else
      if self._sv._growth_timer then
         self._sv._growth_timer:bind(function()
               self:try_grow()
            end)
      end
   end
end

function VineComponent:_get_growth_period(growths_remaining)
   local time
   for _, growth_time in ipairs(self._growth_data.growth_times) do
      if growths_remaining <= growth_time.growths_remaining then
         time = growth_time.time
      else
         if not time then
            time = growth_time.time
         end
         break
      end
   end
   time = time and stonehearth.calendar:parse_duration(time) or 0
   if time > 0 then
      time = stonehearth.town:calculate_growth_period('', time)
   end
   return time
end

-- if no vine group exists, create it; this should only get called on the root entity
function VineComponent:get_vine_group()
   if not self._sv.vine_group then
      self:set_vine_group(radiant.create_controller('stonehearth_ace:vine_group'))
   end

   return self._sv.vine_group
end

-- when a vine grows, it should set the vine group on the new vine entity
function VineComponent:set_vine_group(group)
   self._sv.vine_group = group
   if group then
      group:add_vine(self._entity)
   end

   self.__saved_variables:mark_changed()
end

function VineComponent:toggle_group_harvest_request()
   if self._sv.vine_group then
      self:get_vine_group():toggle_harvest_requests()
   else
      resources_lib.toggle_harvest_requests({self._entity})
   end
end

function VineComponent:set_num_growths_remaining(num)
   self._sv.num_growths_remaining = num or self._growth_data.start_num_growths_remaining
   self.__saved_variables:mark_changed()
end

function VineComponent:_update_models(season)
   for position, seasons in pairs(self._sv._render_models) do
      self._sv.render_options.faces[position].model = seasons[season or 'default']
   end

   self.__saved_variables:mark_changed()
end

function VineComponent:_update_season(transition)
   if self._current_season == transition.to then
      return  -- Already switched.
   elseif transition.t < self._sv._switch_season_time then
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
   self:_stop_growth_timer()
   
   self._growth_roller:clear()
   for dir, chance in pairs(self._growth_data.growth_directions) do
      self._growth_roller:add(dir, chance)
   end

   self._sv.num_growths_remaining = self._sv.num_growths_remaining - 1
   if self._sv.num_growths_remaining >= 0 then
      local new_vine = self:_try_grow()

      if self._growth_roller:is_empty() then
         -- if we explored all growth options, ignore the next X growth attempts on this entity
         self._sv.num_growths_remaining = 0
      else
         self:_start_growth_timer()
      end
   else
      self._sv.num_growths_remaining = 0
   end

   self.__saved_variables:mark_changed()
end

function VineComponent:_try_grow()
   local new_vine
   local grow_location
   local grow_direction

   if self._spread_function.type == SPREAD_FN_DEFAULT then
   
      local neighbors = self:get_neighbors(true)
      if not next(neighbors) then
         return
      end

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
               grow_location = add_location
               grow_direction = dir
               break
            end
         end
      end

   elseif self._spread_function.type == SPREAD_FN_HORIZONTAL_WALK then

      -- talk a random walk starting in a random direction and never going backwards up to max_steps steps
      -- if the resulting space is growable (or there's empty space down to max_drop below it and that space is growable), grow it there
      -- otherwise, step backwards and try a different random starting direction
      -- failing that, grow in that place instead, provided it's at step at least min_steps
      -- otherwise, start over at a different direction
      grow_location, grow_direction = self:_grow_via_horizontal_walk({}, radiant.entities.get_world_grid_location(self._entity), 0, {'x-', 'x+', 'z-', 'z+'})
   end

   if grow_location then
      new_vine = radiant.entities.create_entity(self._uri,
            { owner = self._entity:get_player_id(), ignore_gravity = grow_direction ~= 'y+' and self._growth_data.ignore_gravity })
      
      local vine_comp = new_vine:add_component('stonehearth_ace:vine')
      vine_comp:set_vine_group(self:get_vine_group())
      vine_comp:set_num_growths_remaining(self._sv.num_growths_remaining)

      radiant.terrain.place_entity_at_exact_location(new_vine, grow_location, {force_iconic = false})
      if self._growth_data.randomize_facing then
         radiant.entities.turn_to(new_vine, rng:get_int(0, 3) * 90)
      end
   end

   return new_vine
end

function VineComponent:_grow_via_horizontal_walk(neighbors, location, step_num, step_dirs)
   if step_num >= self._spread_function.max_steps then
      -- try to grow here; since min_steps >= 1, we already know that this space is clear of obstacles
      -- just need to check if the max_drop and terrain type constraints are met
      for i = 1, self._spread_function.max_drop + 1 do
         local test_location = location:translated(Point3(0, -i, 0))
         local neighbor = self:_eval_neighbor_at(test_location)
         if neighbor.is_growable_surface then
            return test_location:translated(Point3(0, 1, 0))
         elseif neighbor.blocked then
            return
         end
      end
   else

      while true do
         if #step_dirs < 1 then
            return
         end

         local try_dir_index = rng:get_int(1, #step_dirs)
         local try_dir = step_dirs[try_dir_index]
         local new_dirs = {}
         for _, dir in ipairs(step_dirs) do
            if dir ~= _opposite_direction[try_dir] then
               table.insert(new_dirs, dir)
            end
         end
         table.remove(step_dirs, try_dir_index)

         local step_location = location:translated(_directions[try_dir])
         local neighbor = neighbors[tostring(step_location)] or self:_eval_neighbor_at(step_location)
         neighbors[tostring(step_location)] = neighbor

         if not neighbor.blocked then
            local grow_location = self:_grow_via_horizontal_walk(neighbors, step_location, step_num + 1, new_dirs)

            if grow_location then
               return grow_location, try_dir
            elseif step_num >= self._spread_function.min_steps then
               return location, try_dir
            end
         end
      end
   end
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
      local neighbor = self:_eval_neighbor_at(location + point) --+ radiant.math.rotate_about_y_axis(point, facing)
      
      neighbors[dir] = neighbor
   end

   return neighbors
end

function VineComponent:_eval_neighbor_at(location)
   local neighbor = {}

   neighbor.location = location
   neighbor.region = _region:translated(neighbor.location)

   -- first check if it's terrain
   local tag = get_block_tag_at(neighbor.location) or 0
   local kind = get_block_kind_from_tag(tag)
   neighbor.terrain_tag = tag
   if next(self._growth_data.terrain_types) then
      neighbor.is_growable_surface = self._growth_data.terrain_types[kind]
   else
      neighbor.is_growable_surface = tag ~= 0
   end

   if neighbor.is_growable_surface then
      neighbor.blocked = true
   else
      -- if it's not terrain (i.e., it's null/air), check if any entities there are vines or solid
      for _, entity in pairs(get_entities_in_region(neighbor.region)) do
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

   return neighbor
end

return VineComponent
