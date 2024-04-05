local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local BlueprintsToBuildingPiecesJob = require 'stonehearth.components.building2.plan.jobs.blueprints_to_building_pieces_job'
local AceBlueprintsToBuildingPiecesJob = class()

local log = radiant.log.create_logger('build.blueprints_to_building_pieces_job')

AceBlueprintsToBuildingPiecesJob._ace_old_create = BlueprintsToBuildingPiecesJob.create
function AceBlueprintsToBuildingPiecesJob:create(job_data)
   self:_ace_old_create(job_data)
   self._sv._insert_craft_requests = job_data.insert_craft_requests
   self._sv._terrain_cutout = job_data.terrain_cutout
   self._sv._terrain_roots = {}
   self._sv._contiguous_terrain_regions = {}
   self._sv._terrain_adjacencies = {}

   local terrain_regions = self._sv._building:get('stonehearth:build2:building'):get_contiguous_terrain_regions()
   for _, region in ipairs(terrain_regions) do
      table.insert(self._sv._contiguous_terrain_regions, {
         region = region,
         root_entity_points = {},
         root_point = nil,
      })
   end
end

AceBlueprintsToBuildingPiecesJob._ace_old_destroy = BlueprintsToBuildingPiecesJob.__user_destroy
function AceBlueprintsToBuildingPiecesJob:destroy()
   if not self:was_consumed() and self._sv._navgrid_proxy then
      radiant.entities.destroy_entity(self._sv._navgrid_proxy)
      self._sv._navgrid_proxy = nil
   end

   self:_ace_old_destroy()
   self._sv._insert_craft_requests = nil
   self._sv._terrain_cutout = nil
   self._sv._terrain_roots = {}
   self._sv._contiguous_terrain_regions = {}
   self._sv._outside_color_regions = {}
   self._sv._terrain_adjacencies = {}

   self._sv._next_outside_color_region = nil
   self._sv._next_terrain_region = nil
   self._sv._next_terrain_root = nil
end

AceBlueprintsToBuildingPiecesJob._ace_old_get_results = BlueprintsToBuildingPiecesJob.get_results
function AceBlueprintsToBuildingPiecesJob:get_results()
   local result = self:_ace_old_get_results()
   result.insert_craft_requests = self._sv._insert_craft_requests
   result.terrain_roots = self._sv._terrain_roots
   result.contiguous_terrain_regions = self._sv._contiguous_terrain_regions
   result.terrain_adjacencies = self._sv._terrain_adjacencies
   result.terrain_cutout = self._sv._terrain_cutout
   return result
end

function AceBlueprintsToBuildingPiecesJob:compute_adjacencies()
   log:info('compute_adjacencies')

   local terrain_entity = radiant._root_entity
   local terrain_id = terrain_entity:get_id()
   self:yield_over_table(self._sv._building_pieces, '_next_piece', function(piece_id, piece)
         log:info('computing adjacencies for piece %s', piece)
         self._sv._terrain_adjacencies[piece_id] = 0
         local adj_map = self._sv._piece_adjacencies[piece_id]
         local origin = radiant.entities.get_world_grid_location(piece)
         local bounds_w = piece:get_component('destination'):get_region():get():get_bounds():translated(origin)

         for _, offset in ipairs(BlueprintsToBuildingPiecesJob.ALL_OFFSETS) do
            local adjs = adj_map:get(offset)
            local adj_bounds_w = bounds_w:get_face(offset):translated(offset)
            
            radiant.terrain.get_entities_in_cube(adj_bounds_w, function(e)
                  local id = e:get_id()
                  if id ~= piece_id and e:get_uri() == 'stonehearth:build2:entities:building_piece' then
                     adjs[id] = e
                  end
               end, self._sv._nav_grid_id)
            
            -- ACE: also check if any horizontal offsets are terrain since they can block building
            if offset.y == 0 and not next(adjs) then
               local clipped_adj_w = _physics:clip_region(Region3(adj_bounds_w), _radiant.physics.Physics.CLIP_SOLID, self._sv._nav_grid_id)
               if clipped_adj_w:get_area() < adj_bounds_w:get_area() then
                  self._sv._terrain_adjacencies[piece_id] = self._sv._terrain_adjacencies[piece_id] + 1
               end
            end
         end
      end)

   log:info('done compute_adjacencies')
   self:incstage()
end

local function allocate_adjacency_map()
   local adjs = _radiant.sim.alloc_point3_map()
   for _, offset in ipairs(BlueprintsToBuildingPiecesJob.ALL_OFFSETS) do
      adjs:add(offset, {})
   end
   return adjs
end

-- ACE: only add a root for pieces that are not mining pieces (and have no pieces below them)
function AceBlueprintsToBuildingPiecesJob:compute_roots()
   log:info('compute_roots')
   local lower_offset = Point3(0, -1, 0)

   self:yield_over_table(self._sv._building_pieces, '_next_piece', function(piece_id, piece)
         local data = piece:get('stonehearth:build2:building_piece'):get_data()
         if radiant.empty(self._sv._piece_adjacencies[piece_id]:get(lower_offset)) then
            local region = piece:get_component('destination'):get_region():get()
            region = radiant.entities.local_to_world(region, piece)
            radiant.terrain.get_entities_in_region(region:translated(lower_offset), function(e)
                  if e:get_id() ~= piece_id and radiant.entities.is_solid_entity(e) then
                     self._sv._roots[piece_id] = piece
                     if data and data.in_terrain then
                        self._sv._terrain_roots[piece_id] = {
                           piece = piece,
                           root_point = nil,
                        }
                     end
                  end
               end, self._sv._nav_grid_id)
         end
      end)

   log:info('done compute_roots: %s roots: %s', radiant.size(self._sv._roots), radiant.util.table_tostring(self._sv._roots))
   self:incstage()
end

function BlueprintsToBuildingPiecesJob:find_root_point()
   log:info('find_root_point')

   if radiant.empty(self._sv._color_regions) then
      self:signal_failure()
      return
   end

   _radiant.sim.topology.force_reflow(self._sv._nav_grid_bounds, self._sv._nav_grid_id)
   local waiting_for_adjacency = true
   _radiant.sim.adjacency.on_adjacency_complete(function()
         waiting_for_adjacency = false
      end, self._sv._nav_grid_id)
   while waiting_for_adjacency do
      self:yield()
   end

   local player_id = radiant.entities.get_player_id(self._sv._building)
   local town = stonehearth.town:get_town(player_id)
   local root_point = self._sv._root_point
   local bc = self._sv._building:get('stonehearth:build2:building')
   local terrain_region = self._sv._terrain_cutout
   local outside_region = terrain_region:extruded('y', 0, 1):extruded('x', 1, 1):extruded('z', 1, 1) - terrain_region

   -- first try finding a root point outside the building bounds
   if not root_point then
      self:yield_over_table(self._sv._outside_color_regions, '_next_outside_color_region', function(c, r)
            local test_point = nil

            for cube in r:each_cube() do
               test_point = Point3(cube.min)
               break
            end

            if not test_point then
               return
            end

            -- We first need to check if this region is even connected to any of the
            -- roots!
            log:info('checking if %s is connected to a root', test_point)
            
            local found = terrain_region:empty() and
                  self:_is_root_point_connected_to_root_entity(test_point) or
                  _radiant.sim.topology.are_strictly_connected(test_point, outside_region, self._sv._nav_grid_id)
            if found and self:_is_root_point_connected_to_citizen(test_point, town) then
               root_point = test_point
               -- Stop iterating over the table
               return true
            end
         end)
   end

   -- we also need to find root points in each contiguous terrain region
   self:yield_over_table(self._sv._contiguous_terrain_regions, '_next_terrain_region', function(i, ctr)
         -- for each contiguous terrain region, try to find a connected root point in the nav grid
         for c, r in pairs(self._sv._color_regions) do
            local test_point = nil
            for cube in r:each_cube() do
               log:debug('checking _contiguous_terrain_regions if %s is connected to %s', ctr.region:get_bounds(), cube)
               test_point = cube.min
               break
            end

            if ctr.region:contains(test_point) then
               log:debug('found root point %s in %s', test_point, ctr.region:get_bounds())
               ctr.root_point = test_point
               return
            end
         end
      end)

   -- finally, if terrain was involved, try to find a root point directly above each root entity
   -- preferably not colliding with any other build pieces
   local building_region = bc:get_total_building_region()
   self:yield_over_table(self._sv._terrain_roots, '_next_terrain_root', function(i, tr)
         local piece = tr.piece
         local region = piece:get_component('destination'):get_region():get()
         region = radiant.entities.local_to_world(region, piece)
         local above = region:translated(Point3.unit_y)

         local test_point = nil
         local unocuppied = above - building_region
         log:debug('checking _terrain_roots above region %s => unoccupied region %s', above:get_bounds(), unocuppied:get_bounds())
         for cube in unocuppied:each_cube() do
            log:debug('checking unoccupied cube %s', cube)
            test_point = cube.min
            break
         end

         if not test_point then
            log:debug('no unoccupied cubes; checking above region %s', above:get_bounds())
            for cube in above:each_cube() do
               test_point = cube.min
               break
            end
         end

         tr.root_point = test_point

         -- also check if this root entity is within any of the contiguous terrain regions
         -- and add it to that region's list
         for i, ctr in ipairs(self._sv._contiguous_terrain_regions) do
            if ctr.region:intersects_region(region) then
               table.insert(ctr.root_entity_points, test_point)
               tr.contiguous_terrain_region_index = i
               break
            end
         end
      end)

   if not root_point then
      log:info('could not find connected citizen; looking for a large connected region.')
      -- Couldn't find a connected citizen!  Pick any point in the largest area that has a root in it.
      local largest = nil
      local largest_area = 0

      for c, r in pairs(self._sv._outside_color_regions) do
         if r:get_area() > largest_area then
            local test_point = nil
            for cube in r:each_cube() do
               test_point = cube.min
               break
            end
            local found = false
            for _, root_piece in pairs(self._sv._roots) do
               local adj_w = radiant.entities.get_world_adjacency_region(root_piece)
               if _radiant.sim.topology.are_connected(test_point, adj_w, self._sv._nav_grid_id) then
                  found = true
                  break
               end
            end

            if found then
               largest_area = r:get_area()
               largest = r
            end
         end
      end

      if largest then
         for cube in largest:each_cube() do
            root_point = cube.min
            break
         end
      end
   end

   if not root_point then
      log:info('could not find connected region; defaulting to largest region.')
      -- Couldn't find a connected citizen!  Pick any point in the largest area that has a root in it.
      local largest = nil
      local largest_area = 0

      for c, r in pairs(self._sv._outside_color_regions) do
         if r:get_area() > largest_area then
            largest_area = r:get_area()
            largest = r
         end
      end

      for cube in largest:each_cube() do
         root_point = cube.min
         break
      end
   end
   log:info('done find_root_point')

   if not root_point then
      self:signal_failure()
      return
   end

   self._sv._root_point = root_point
   self:incstage()
end

function AceBlueprintsToBuildingPiecesJob:_is_root_point_connected_to_root_entity(test_point)
   -- We first need to check if this region is even connected to any of the
   -- roots!
   for _, root_piece in pairs(self._sv._roots) do
      local adj_w = radiant.entities.get_world_adjacency_region(root_piece)

      log:spam('looking at adj_w %s', adj_w:get_bounds())
      if _radiant.sim.topology.are_strictly_connected(test_point, adj_w, self._sv._nav_grid_id) then
         log:spam('connected to %s', test_point)
         return true
      end
   end

   return false
end

function AceBlueprintsToBuildingPiecesJob:_is_root_point_connected_to_citizen(test_point, town)
   for _, citizen in town:get_citizens():each() do
      local pos = radiant.entities.get_world_grid_location(citizen)

      if pos then
         log:spam('checking if %s and %s are connected', test_point, pos)
         if _radiant.sim.topology.are_strictly_connected(pos, test_point, 0) then
            -- Pick any point in that region, since it "must" be connected.
            -- This is not actually true!  Rather, it is true that, WITHOUT the
            -- building, any point in that region is connected to the hearthling.
            -- With the building in place, it may become the case that it is no longer
            -- connected to that point!  We cannot do better without being able to
            -- trivially duplicate the entire world and run connectivity tests.

            log:info('found root to hearthling!')
            return true
         end
      end
   end
end

function AceBlueprintsToBuildingPiecesJob:clone_nav_grid()
   local nav_grid_bounds = Cube3(self._sv._building_bounds)
   nav_grid_bounds:grow(Point3(nav_grid_bounds.min.x, -1000, nav_grid_bounds.min.z))
   nav_grid_bounds:grow(Point3(nav_grid_bounds.max.x, 1000, nav_grid_bounds.max.z))

   -- Inflate this a little to account for scaffolding that is on the sides.
   self._sv._nav_grid_bounds = nav_grid_bounds:inflated(Point3(1, 1, 1))

   -- don't use the bounds or entities for cloning; just make it blank,
   -- then copy the terrain region minus what we want to mine out
   -- and put it into the rcs of a proxy entity that we place on that root entity
   -- self._sv._nav_grid_id = _radiant.sim.clone_nav_grid(self._sv._nav_grid_bounds, radiant.entities.get_player_id(self._sv._building), self._sv._ignored_entities)
   self._sv._nav_grid_id = _radiant.sim.clone_nav_grid(Cube3(), radiant.entities.get_player_id(self._sv._building), {})
   local new_root = _radiant.sim.get_entity(_radiant.sim.get_nav_grid_root(self._sv._nav_grid_id))

   log:info('cloned new nav_grid with id %s', self._sv._nav_grid_id)

   -- Now, collect up all the like-colored regions in this new nav-grid, and then
   -- store them (after removing the building's contribution)
   _radiant.sim.topology.set_manual_mode(self._sv._nav_grid_id, true)

   -- ACE: copy the terrain region within the bounds
   local terrain_region = radiant.terrain.intersect_cube(self._sv._nav_grid_bounds)
   local proxy = radiant.entities.create_entity('stonehearth_ace:object:navgrid_proxy')
   local rcs = proxy:add_component('region_collision_shape')
   rcs:set_region(_radiant.sim.alloc_region3())
   rcs:get_region():modify(function(cursor)
         cursor:copy_region(terrain_region - self._sv._terrain_cutout)

         -- also copy the finished collision regions of existing buildings
         for _, b in stonehearth.building:get_buildings():each() do
            local bc = b:get('stonehearth:build2:building')
            if bc:completed() then
               local r = bc:get_total_building_region()
               if r then
                  cursor:add_region(r)
               else
                  log:error('building %s has no total building region!', radiant.entities.get_custom_name(b))
               end
               cursor:add_region(bc:get_total_building_region())
            end
         end
      end)
   radiant.terrain.place_entity_at_exact_location(proxy, Point3.zero, { root_entity = new_root })
   self._sv._navgrid_proxy = proxy

   _radiant.sim.topology.force_reflow(self._sv._nav_grid_bounds, self._sv._nav_grid_id)

   local waiting_for_adjacency = true
   _radiant.sim.adjacency.on_adjacency_complete(function()
         waiting_for_adjacency = false
      end, self._sv._nav_grid_id)
   while waiting_for_adjacency do
      self:yield()
   end


   -- ACE: save the raw regions for later, but also subtract out for a copy
   self._sv._color_regions = _radiant.sim.topology.to_regions(self._sv._nav_grid_bounds, self._sv._nav_grid_id)
   self._sv._outside_color_regions = {}
   for c, r in pairs(self._sv._color_regions) do
      local r2 = Region3(r)
      r2:subtract_cube(self._sv._building_bounds)
      self._sv._outside_color_regions[c] = r2
   end

   self:incstage()
end

-- TODO: if a mining zone exists, we need to split the building pieces on that region
-- so everything within mining zones can be built first (from the inside) and then
-- normal build planning can take over for the rest of the building (from the outside)
function AceBlueprintsToBuildingPiecesJob:structures_to_building_pieces()
   log:info('structures_to_building_pieces')

   local new_root = _radiant.sim.get_entity(_radiant.sim.get_nav_grid_root(self._sv._nav_grid_id))
   self:yield_over_table(self._sv._structures, '_next_structure', function(s_id, s)
         local building_pieces = s:get('stonehearth:build2:structure'):to_buildable_pieces(self._sv._terrain_cutout)
         local structure_origin = s:get('stonehearth:build2:structure'):get_origin()
         local roof_like = s:get('stonehearth:build2:structure'):is_old_roof()

         for _, building_piece_region in ipairs(building_pieces) do
            -- Create the temp building piece entity with this world-space region
            local piece = radiant.entities.create_entity('stonehearth:build2:entities:building_piece')
            piece:get('stonehearth:build2:building_piece'):set_data(self._sv._building, false,
                  { in_terrain = self._sv._terrain_cutout:intersects_region(building_piece_region:translated(structure_origin)) })

            -- TODO: don't want to auto-update; need to factor and borrow logic from chunk.lua
            piece:get('destination'):set_region(radiant.alloc_region3())
                                    :set_adjacent(radiant.alloc_region3())
                                    :set_auto_update_adjacent(true)
            piece:get('region_collision_shape'):set_region(radiant.alloc_region3())

            local building_piece_min = building_piece_region:get_bounds().min
            local building_piece_origin = building_piece_min + structure_origin

            local building_piece_region_ls = building_piece_region:translated(-building_piece_min)
            piece:get('destination'):get_region():modify(function(cursor)
                  cursor:copy_region(building_piece_region_ls)
               end)
            piece:get('region_collision_shape'):get_region():modify(function(cursor)
                  cursor:copy_region(building_piece_region_ls)
               end)

            local bounds_w = building_piece_region_ls:translated(building_piece_origin)
            local bounds_size = bounds_w:get_bounds():get_size()
            if bounds_size.y == 1 or (bounds_size.x > 1 and bounds_size.z > 1) then
               self._sv._envelope_w:add_region(bounds_w:extruded('y', 0, 2))
            else
               self._sv._envelope_w:add_region(bounds_w)
            end

            log:info('placing building_piece %s in the world at %s', piece, building_piece_region_ls:translated(building_piece_origin):get_bounds())
            radiant.terrain.place_entity_at_exact_location(piece, building_piece_origin, { root_entity = new_root })

            local building_piece_id = piece:get_id()
            self._sv._building_pieces[building_piece_id] = piece
            self._sv._piece_adjacencies[building_piece_id] = allocate_adjacency_map()
            self._sv._piece_2_structures[building_piece_id] = s

            if roof_like then
               self._sv._roof_like_pieces[building_piece_id] = s_id
            end
         end
      end)

   log:info('done structures_to_building_pieces: %s building_pieces', radiant.size(self._sv._building_pieces))
   self:incstage()
end

return AceBlueprintsToBuildingPiecesJob
