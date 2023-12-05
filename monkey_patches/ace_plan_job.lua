local NewFixtureNode = require 'stonehearth.components.building2.plan.nodes.new_fixture_node'
local NewChunkNode = require 'stonehearth.components.building2.plan.nodes.new_chunk_node'
local NewMiningNode = require 'stonehearth.components.building2.plan.nodes.new_mining_node'
local ReachabilityNode = require 'stonehearth.components.building2.plan.nodes.reachability_node'
local ReduceScaffoldingNode = require 'stonehearth.components.building2.plan.nodes.reduce_scaffolding_node'
local CrafterJobsNode = require 'stonehearth.components.building2.plan.nodes.crafter_jobs_node'

local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Cube3   = _radiant.csg.Cube3

local log = radiant.log.create_logger('build.plan_job')

local ComputePlanJob = require 'stonehearth.components.building2.plan.jobs.plan_job'
local AceComputePlanJob = class()

AceComputePlanJob._ace_old_create = ComputePlanJob.create
function AceComputePlanJob:create(job_data)
   self:_ace_old_create(job_data)
   self._sv._insert_craft_requests = job_data.insert_craft_requests
   self._sv._terrain_roots = job_data.terrain_roots
   self._sv._contiguous_terrain_regions = job_data.contiguous_terrain_regions
   self._sv._terrain_cutout = job_data.terrain_cutout

   log:debug('terrain roots: %s', radiant.util.table_tostring(self._sv._terrain_roots))
   log:debug('contiguous terrain regions: %s', radiant.util.table_tostring(self._sv._contiguous_terrain_regions))
   log:debug("terrain cutout: %s", self._sv._terrain_cutout:get_bounds())
end

function AceComputePlanJob:compute_crafter_jobs()
   log:info('compute_crafter_jobs')

   local resources, items = self._sv._building:get('stonehearth:build2:building'):get_costs()

   self._sv._plan:push_node_front(CrafterJobsNode(self._sv._building, items, resources, self._sv._insert_craft_requests))

   log:info('done compute_crafter_jobs')
   self:incstage()
end

function AceComputePlanJob:_get_root_points(piece_id, data, region)
   -- if the piece is in terrain, and is a terrain root entity, use the corresponding contiguous terrain root point
   -- if it's in the terrain but isn't a root entity, use the root entity points for that contiguous terrain region
   -- otherwise, use the outside root point
   local terrain_root = self._sv._terrain_roots[piece_id]
   local contiguous_terrain_regions = self._sv._contiguous_terrain_regions
   local index = terrain_root and terrain_root.contiguous_terrain_region_index
   if index then
      return { self._sv._contiguous_terrain_regions[index].root_point }
   elseif data.in_terrain then
      for _, contiguous_region in pairs(self._sv._contiguous_terrain_regions) do
         if contiguous_region.region:intersects_region(region) then
            if #contiguous_region.root_entity_points > 0 then
               return contiguous_region.root_entity_points
            end
            break
         end
      end
   end

   return { self._sv._root_location }
end

function AceComputePlanJob:compute_build_up_plan()
   log:info('compute_build_up_plan @ %s', self._sv._root_location)

   local bc = self._sv._building:get_component('stonehearth:build2:building')
   local player_id = radiant.entities.get_player_id(self._sv._building)

   local root_point = self._sv._root_location
   _radiant.sim.topology.force_reflow(self._sv._nav_grid_bounds, self._sv._nav_grid_id)

   while next(self._sv._in_progress_deps) or next(self._sv._remaining_plan_building_pieces) or next(self._sv._skipped_plan_building_pieces) do
      log:spam('plan loop')
      -- Topology and adjacency must reflow before we can compute this round of building_pieces!
      self:_wait_for_adjacency_completion()
      self:_wait_for_topology_step()

      local fixture = NewFixtureNode(self._sv._building)
      local fake_mining_node = NewMiningNode(self._sv._building)
      local with_mining = NewChunkNode(self._sv._building)
      local anti_scaffolding = ReduceScaffoldingNode(self._sv._building)
      local reachability = ReachabilityNode(self._sv._building)
      local made_progress = false
      local num_attempts = 0
      local root_points_cache = {}

      local skipped_building_pieces = nil
      while num_attempts < 3 and not made_progress do
         skipped_building_pieces = {}
         for piece_id, _ in pairs(self._sv._in_progress_deps) do
            -- First, find the support region for the building_piece.  This is the region that hearthlings will need
            -- to be able to stand on, in order to build the building_piece.  To do this, we first need to see if
            -- there is scaffolding we need to build.
            local piece = self._sv._building_pieces[piece_id]
            local piece_comp = piece:get('stonehearth:build2:building_piece')
            local piece_origin = radiant.entities.get_world_grid_location(piece)
            local piece_region = radiant.entities.get_world_region(piece)
            local piece_data = piece_comp:get_data()
            local root_points = root_points_cache[piece_id] or self:_get_root_points(piece_id, piece_data, piece_region)
            log:debug('looking at %s (%s) %s', piece_id, piece_data and radiant.util.table_tostring(piece_data) or 'nil', piece_region:get_bounds())
            root_points_cache[piece_id] = root_points

            local processed = false
            if piece_comp:is_fixture() then
               processed = self:_process_fixture(piece, piece_origin, root_points, fixture, reachability)
            else
               processed = self:_process_chunk(piece, piece_origin, bc, root_points, with_mining, fake_mining_node, anti_scaffolding, reachability)
            end

            if not processed then
               log:info('could not find a home for %s (%s).  deferring to next round.', piece_id, piece_region:get_bounds())
               skipped_building_pieces[piece_id] = piece_region
            else
               if self._debug_pieces[piece_id] then
                  stonehearth.debug_shapes:destroy_box(self._debug_pieces[piece_id])
                  self._debug_pieces[piece_id] = nil
               end
               made_progress = true
            end
         end

         for piece_id, _ in pairs(skipped_building_pieces) do
            self:_enque_skipped_building_piece(piece_id)
            self._sv._in_progress_deps[piece_id] = nil
         end

         num_attempts = num_attempts + 1

         if not made_progress and num_attempts < 3 then
            -- Make a last-ditch attempt to find _anything_ we can enqueue.
            self._sv._in_progress_deps = self:_queue_next_buildable_building_pieces(num_attempts)
         end
      end

      if not made_progress then
         local piece_regions = {}
         for piece_id, piece_region in pairs(skipped_building_pieces) do
            log:error('could not figure out piece %s', piece_id)
            table.insert(piece_regions, piece_region)
         end

         self:signal_failure()
         self:set_failure_payload(piece_regions)
         return
      end

      -- TODO: fix.
      -- Nah, this isn't right.  Complete and Correct is going to be: check scaffolding + reachability ladders and
      -- see if any of those land on building_pieces we are using RIGHT NOW.  This will result in a (possibly linear!) ordering
      -- of all the building_pieces in this round, potentially even with anti scaffolding/etc thrown in; this is another good
      -- reason for a heuristic that also biases away from relying on stuff that is being used be right now.
      if not anti_scaffolding:empty() then
         self._sv._plan:push_node_front(anti_scaffolding)
      end
      if not fixture:empty() then
         self._sv._plan:push_node_front(fixture)
      end
      if not with_mining:empty() then
         self._sv._plan:push_node_front(with_mining)
      end
      if not reachability:empty() then
         self._sv._plan:push_node_front(reachability)
      end
      -- Building_Pieces are processed, so change their region collision type to 'none' so that they are effectively
      -- gone from the world.  This means we can still query them to see if they are 'there', but the topology
      -- of the world will change as if the building_piece were removed.
      for piece_id, _ in pairs(self._sv._in_progress_deps) do
         self:_remove_inv_dependency(piece_id)
         self._sv._building_pieces[piece_id]:get('stonehearth:build2:building_piece'):mark_consumed()
      end

      self._sv._in_progress_deps = self:_queue_next_buildable_building_pieces(0)
      self:maybe_yield()
   end
   assert(not next(self._sv._remaining_plan_piece_inv_deps))

   -- ACE: we don't actually want to restore any terrain, so just don't save the displaced terrain
   -- self._sv._terrain_region_w:clear()
   -- do all the mining first!
   local mining_region = self._sv._terrain_cutout
   log:debug('mining region: %s (%s)', tostring(mining_region), mining_region:get_bounds())
   if not mining_region:empty() then
      log:debug('adding mining node')
      local mining_node = NewMiningNode(self._sv._building)
      mining_node:add_terrain_region(mining_region)
      self._sv._plan:push_node_front(mining_node)
   end

   log:info('done compute_build_up_plan')
   self:incstage()
end

local ALL_NORMALS = { Point3(0, 0, 1), Point3(1, 0, 0), Point3(0, 0, -1), Point3(-1, 0, 0) }

-- TODO: LOTS of region arithmetic, but some of it could just use cubes--remember, building_pieces are just
-- rectangular prisms!
local function _compute_single_scaffolding_region(piece_region_l, normal, piece_origin, nav_grid_id)
   local scaffold_region_w = piece_region_l:translated(normal + piece_origin) - piece_region_l:translated(piece_origin)
   log:info('trying scaffolding region at %s', scaffold_region_w:get_bounds())

   -- TODO: taken from old scaffolding.  Why...is this a thing?  Re-test with the suggested case.
   -- Make sure the scaffolding doesn't extend beyond the world (otherwise, our "get_area" results will be
   -- wrong.  This can happen with towers that are the highest thing in the world.)
   scaffold_region_w = _physics:clip_region_to_world_bounds(scaffold_region_w, nav_grid_id)

   if _physics:clip_region(scaffold_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id):get_area() ~= scaffold_region_w:get_area() then
      log:info('%s blocked by world (1).  rejecting.', scaffold_region_w:get_bounds())
      return nil
   end

   -- In the case of non-wall pieces, hearthlings will need to build scaffolding all the way up,
   -- so make sure we can do so without hitting their heads.
   local piece_size = piece_region_l:get_bounds():get_size()

   if piece_size.y ~= 1 and (piece_size.x == 1 or piece_size.z == 1) then
      -- For wall/column pieces, we only need to build scaffolding up to the highest
      -- point of the wall, minus *3* (to accommodate hearthling height.)
      local new_region_cube_w = scaffold_region_w:get_bounds()
      new_region_cube_w.max.y = new_region_cube_w.max.y - 3 -- ACE BUILD HEIGHT
      if new_region_cube_w.max.y <= new_region_cube_w.min.y then
         new_region_cube_w.min.y = new_region_cube_w.max.y - 1
      end
      scaffold_region_w = Region3(new_region_cube_w)
      scaffold_region_w = _physics:clip_region(scaffold_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id)

      if scaffold_region_w:empty() then
         log:info('scaffolding unnecessary. rejecting.')
         return nil
      end
   end

   local extruded_w = scaffold_region_w:extruded('y', 0, 3) -- ACE BUILD HEIGHT
   if _physics:clip_region(extruded_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id):get_area() ~= extruded_w:get_area() then
      log:info('extruded %s blocked by world.  rejecting.', extruded_w:get_bounds())
      return nil
   end

   -- Project scaffolding region _down_ to hit stuff.
   local proposed_scaffolding_w = _physics:project_region(scaffold_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id)

   if proposed_scaffolding_w:get_area() == 0 or proposed_scaffolding_w:get_bounds().min.y == _physics:get_world_bounds(nav_grid_id).min.y then
      log:info('proposed scaffolding projection failed.')
      return nil
   end

   -- Finally, check for non-solid things in our way (like doors.)
   local portals = radiant.terrain.get_entities_in_region(proposed_scaffolding_w, function(e)
         return not e:get('stonehearth:build2:building_piece'):is_consumed()
      end, nav_grid_id)

   if not radiant.empty(portals) then
      log:info('something in the way: %s', radiant.first(portals))
      return nil
   end

   log:info('going with %s', proposed_scaffolding_w:get_bounds())
   return proposed_scaffolding_w
end

local function _compute_single_non_scaffolding_region(piece_region_l, normal, piece_origin, nav_grid_id)
   local region_w = piece_region_l:translated(normal + piece_origin) - piece_region_l:translated(piece_origin)
   log:info('trying non-scaffolding region at %s', region_w:get_bounds())

   -- TODO: taken from old scaffolding.  Why...is this a thing?  Re-test with the suggested case.
   -- Make sure the scaffolding doesn't extend beyond the world (otherwise, our "get_area" results will be
   -- wrong.  This can happen with towers that are the highest thing in the world.)
   region_w = _physics:clip_region_to_world_bounds(region_w, nav_grid_id)

   -- see if a standable region clipped to top or bottom is unblocked
   local size = region_w:get_bounds():get_size()
   local standable_region_w = region_w:extruded('y', math.max(0, 3 - size.y), 0)
   local standable_failed = false
   if _physics:clip_region(standable_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id):get_area() ~= standable_region_w:get_area() then
      -- blocked from the top; if y size < 3, try again from the bottom
      if size.y < 3 then
         standable_region_w = region_w:extruded('y', 0, math.max(0, 3 - size.y))
         if _physics:clip_region(standable_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id):get_area() ~= standable_region_w:get_area() then
            -- blocked from the bottom! but, if it's only 1 high, try from the middle!
            if size.y == 1 then
               standable_region_w = region_w:extruded('y', 1, 1)
               if _physics:clip_region(standable_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id):get_area() ~= standable_region_w:get_area() then
                  standable_failed = true
               end
            else
               standable_failed = true
            end
         end
      else
         standable_failed = true
      end
   end

   if standable_failed then
      log:info('standable %s blocked by world.  rejecting.', standable_region_w:get_bounds())
      return false
   end

   local new_region_cube_w = standable_region_w:get_bounds():get_face(-Point3.unit_y)
   region_w = Region3(new_region_cube_w)

   if _physics:clip_region(region_w:translated(-Point3.unit_y), _radiant.physics.Physics.CLIP_SOLID, nav_grid_id):get_area() == 0 then
      log:info('success: no scaffolding necessary for standable region %s', standable_region_w:get_bounds())
      return region_w
   end

   return nil
end

local function _compute_adjacent(piece_entity, piece_origin)
   local dest = piece_entity:get('destination'):get_region():get()
   local adj = piece_entity:get('destination'):get_adjacent():get()
   -- Subtract out the destination, because for this static analysis, we can't stand
   -- on ourselves to build ourselves :P
   local adj_w = (adj - dest):translated(piece_origin)

   -- We want to allow anyone standing over + next to this region to be able to build it.
   adj_w:add_region(adj_w:translated(Point3(0, 1, 0)))

   return adj_w
end

local function _compute_fixture_adjacent(piece_entity, piece_origin)
   local dest = piece_entity:get('destination'):get_region():get()
   local adj = piece_entity:get('destination'):get_adjacent():get()
   -- Subtract out the destination, because for this static analysis, we can't stand
   -- on ourselves to build ourselves :P
   local adj_w = (adj - dest):translated(piece_origin)

   return adj_w
end

local function _is_blocked(piece_entity, nav_grid_id)
   local piece_cube_w = radiant.entities.get_world_region(piece_entity):get_bounds()
   local piece_size = piece_cube_w:get_size()
   local colliding = {}

   local standable_w = Cube3(
      Point3(piece_cube_w.min.x, piece_cube_w.max.y, piece_cube_w.min.z),
      Point3(piece_cube_w.max.x, piece_cube_w.max.y + 3, piece_cube_w.max.z))
   colliding = radiant.terrain.get_entities_in_cube(standable_w, function(e)
      return
         e:get_uri() == 'stonehearth:entities:navgrid_proxy' or
         e:get_uri() == 'stonehearth_ace:object:navgrid_proxy' or
         (e:get_uri() == 'stonehearth:build2:entities:building_piece' and
         e:get('region_collision_shape') and
         e:get('region_collision_shape'):get_region_collision_type() == _radiant.om.RegionCollisionShape.SOLID)
   end, nav_grid_id)

   if not radiant.empty(colliding) then
      log:debug('%s blocked by %s', piece_entity, radiant.util.table_tostring(colliding))
      local first_colliding = colliding[next(colliding)]
      if first_colliding:get_uri() == 'stonehearth:entities:navgrid_proxy' or
            first_colliding:get_uri() == 'stonehearth_ace:object:navgrid_proxy' then
         log:debug('navgrid proxy region bounds: %s', radiant.entities.get_world_bounds(first_colliding))
      end
   end

   return not radiant.empty(colliding)
end

local function _select_best_scaffolding(all_scaffolding, long_axis_normal)
   local remaining = {}

   -- long-axis wins first
   if long_axis_normal then
      for _, scaffolding in ipairs(all_scaffolding) do
         if scaffolding.normal == long_axis_normal or scaffolding.normal == -long_axis_normal then
            table.insert(remaining, scaffolding)
         end
      end
   else
      for _, scaffolding in ipairs(all_scaffolding) do
         table.insert(remaining, scaffolding)
      end
   end

   local area_winner = nil
   local area = 999999
   for _, scaffolding in ipairs(remaining) do
      local new_area = scaffolding.region_w:get_area()
      if new_area < area then
         area = new_area
         area_winner = scaffolding
      end
   end

   return area_winner.region_w, area_winner.normal
end

local SUCCESS = 0
local NO_VALID_LOCATION = 1

local function _compute_single_ladder_placement(piece_region_l, normal, piece_origin, nav_grid_id)
   -- Compute a new adjacency for the piece, but only consider the bottom-most part of it (since
   -- we're trying to get ourselves a ladder to here.)
   local piece_test_region_w = piece_region_l:translated(normal + piece_origin) - piece_region_l:translated(piece_origin)
   piece_test_region_w = piece_test_region_w:peel(Point3(0, 1, 0)):translated(-Point3.unit_y)

   for pt_w in piece_test_region_w:each_point() do
      log:info('trying to put a ladder at %s', pt_w)
      local test_region_w = Region3(Cube3(pt_w, pt_w + Point3(1, 3, 1)))

      test_region_w = _physics:clip_region_to_world_bounds(test_region_w, nav_grid_id)

      if _physics:clip_region(test_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id):get_area() ~= 3 then
         log:info('blocked by world.  rejecting.')
      else
         -- Project scaffolding region _down_ to hit stuff.
         local test_region_w = _physics:project_region(test_region_w, _radiant.physics.Physics.CLIP_SOLID, nav_grid_id)

         if test_region_w:get_area() == 0 or test_region_w:get_bounds().min.y == _physics:get_world_bounds(nav_grid_id).min.y then
            log:info('proposed ladder projection failed.')
         else
            local bounds = test_region_w:get_bounds()
            log:info('going with %s', bounds)
            return bounds.min, Point3(bounds.min.x, bounds.max.y - 1, bounds.min.z)
         end
      end
   end
   log:info('could not find a place for a ladder')
   return nil, nil
end

local function _requires_ladder(piece_entity, piece_origin, nav_grid_id)
   local piece_dest = piece_entity:get_component('destination')
   local piece_region_l = piece_dest:get_region():get()

   local adj_w = _compute_fixture_adjacent(piece_entity, piece_origin)

   for point in adj_w:each_point() do
      log:spam('looking at %s', point)
      -- TODO: nasty for large areas!  Consider 'is_any_standable' with a supplied region.
      -- (Will at least keep us in C++ land.)
      if _physics:is_standable(point, nav_grid_id) and
         not _physics:is_blocked(point + Point3(0, 1, 0), nav_grid_id) and
         not _physics:is_blocked(point + Point3(0, 2, 0), nav_grid_id) then
         log:info('fixture does not require a ladder')
         return false
      end
   end

   log:info('fixture needs a ladder')
   return true
end

local function _select_best_ladder(all_ladders)
   local height_winner = nil
   local height = 999999
   for _, ladder in ipairs(all_ladders) do
      local new_height = ladder.top_pt_w.y - ladder.bottom_pt_w.y
      if new_height < height then
         height = new_height
         height_winner = ladder
      end
   end

   return height_winner
end

local function _compute_fixture_ladder_region(piece_entity, piece_origin, nav_grid_id)
   local piece_region = piece_entity:get_component('destination'):get_region():get()

   local results = {}
   for _, normal in ipairs(ALL_NORMALS) do
      local bottom_pt_w, top_pt_w = _compute_single_ladder_placement(piece_region, normal, piece_origin, nav_grid_id)
      if bottom_pt_w then
         table.insert(results, {
               top_pt_w = top_pt_w,
               bottom_pt_w = bottom_pt_w,
               normal = normal,
            })
      end
   end

   if not next(results) then
      return nil, nil, nil
   end
   local best = _select_best_ladder(results)
   return best.bottom_pt_w, best.top_pt_w, best.normal
end

-- Returns (scaffolding_region?, normal?, err)
local function _compute_scaffolding_region(piece_entity, piece_origin, nav_grid_id)
   local piece_region = piece_entity:get_component('destination'):get_region():get()
   local piece_size = piece_region:get_bounds():get_size()
   local long_axis_normal = nil

   -- Don't allow 1xYx1 chunks to have a long_axis_normal; this is safe (since we
   -- can't trap hearthlings inbetween their work like with actual wall) and makes
   -- more things buildable.
   if piece_size.x > 1 or piece_size.z > 1 then
      if piece_size.x == 1 then
         long_axis_normal = Point3(1, 0, 0)
      elseif piece_size.z == 1 then
         long_axis_normal = Point3(0, 0, 1)
      end
   end

   local results = {}
   for i, normal in ipairs(ALL_NORMALS) do
      if not long_axis_normal or (long_axis_normal == normal or long_axis_normal == -normal) then
         local scaffolding_region_w = _compute_single_scaffolding_region(piece_region, normal, piece_origin, nav_grid_id)
         if scaffolding_region_w then
            table.insert(results, {
                  region_w = scaffolding_region_w,
                  normal = normal,
               })
         end
      end
   end

   if not next(results) then
      return nil, nil
   end
   local best_region_w, best_normal = _select_best_scaffolding(results, long_axis_normal)
   return best_region_w, best_normal
end

local function _compute_non_scaffolding_region(piece_entity, piece_origin, nav_grid_id)
   local piece_region = piece_entity:get_component('destination'):get_region():get()
   local piece_size = piece_region:get_bounds():get_size()
   local long_axis_normal = nil

   -- Don't allow 1xYx1 chunks to have a long_axis_normal; this is safe (since we
   -- can't trap hearthlings inbetween their work like with actual wall) and makes
   -- more things buildable.
   if piece_size.x > 1 or piece_size.z > 1 then
      if piece_size.x == 1 then
         long_axis_normal = Point3(1, 0, 0)
      elseif piece_size.z == 1 then
         long_axis_normal = Point3(0, 0, 1)
      end
   end

   local results = {}
   for i, normal in ipairs(ALL_NORMALS) do
      if not long_axis_normal or (long_axis_normal == normal or long_axis_normal == -normal) then
         local region_w = _compute_single_non_scaffolding_region(piece_region, normal, piece_origin, nav_grid_id)
         if region_w then
            return region_w
         end
      end
   end

   return nil
end

local function _compute_support(region_w)
   -- Just want the last 'layer' of the region.
   local support_region_w = region_w:peel(Point3(0, 1, 0))
   log:info('support region is %s', support_region_w:get_bounds())
   return support_region_w
end

local function _compute_anti_scaffolding(scaffolding_region_w, nav_grid_id)
   -- Does the scaffolding region intersect any future structures?  If so,
   -- return what the reduced form of the scaffolding looks like.

   local colliding = radiant.terrain.get_entities_in_region(scaffolding_region_w, function(e)
         return e:get_uri() == 'stonehearth:build2:entities:building_piece'
      end, nav_grid_id)

   if radiant.empty(colliding) then
      return nil
   end

   log:info('scaffolding is in the way of a future structure %s', radiant.first(colliding))

   local new_region_w = scaffolding_region_w:duplicate()
   local scaffolding_region_y = new_region_w:get_bounds().max.y
   local total_collider_w = Region3()
   for _, collider in pairs(colliding) do
      total_collider_w:add_region(radiant.entities.get_world_region(collider))
   end

   -- Walk along the base of the scaffolding, looking for the parts that are obstructed
   -- by the colliders.  Remove those pieces, and if the collider obstructs a hearthling,
   -- completely remove the vertical section.
   local scaffolding_base_w = scaffolding_region_w:peel(Point3(0, 1, 0))

   for pt in scaffolding_base_w:each_point() do
      local sample_pt = pt + Point3.zero
      local end_pt = nil
      while scaffolding_region_w:contains(sample_pt) do
         if total_collider_w:contains(sample_pt) then
            end_pt = sample_pt
            break
         end
         sample_pt.y = sample_pt.y + 1
      end

      if end_pt ~= nil then
         if end_pt.y - sample_pt.y < 3 then
            end_pt = pt
         end

         local remove = Cube3(end_pt, end_pt + Point3(1, 9999999, 1))
         new_region_w:subtract_cube(remove)
      end
   end

   log:info('new scaffolding region will be %s', new_region_w:get_bounds(), new_region_w:get_area())

   -- TODO: this might not be a prism.  Problem?
   return new_region_w
end

local function _compute_mining_region(piece_entity, piece_origin, nav_grid_id)
   return radiant.terrain.intersect_region(piece_entity:get('destination'):get_region():get():translated(piece_origin), nav_grid_id)
end

local function _connected_to_root(root_point, region_w, needs_scaffolding, nav_grid_id)
   if not needs_scaffolding then
      return _radiant.sim.topology.are_connected(root_point, region_w, nav_grid_id)
   end

   -- For a scaffolding base, EVERY single point needs to be reachable (in order to ensure that a
   -- hearthling can hammer each piece of scaffolding, and reach any ladder).
   return _radiant.sim.topology.are_all_connected(root_point, region_w, nav_grid_id)
end

local function _connected_to_any_root(root_points, region_w, needs_scaffolding, nav_grid_id)
   for _, root_point in ipairs(root_points) do
      if _connected_to_root(root_point, region_w, needs_scaffolding, nav_grid_id) then
         return true
      end
   end
   return false
end

local function _wire_topology_paths_to_root(start_point, region_w, is_scaffolding, nav_grid_id)
   local ladder_points = {}
   local ladder_points_map = radiant.alloc_point3_map()
   if is_scaffolding then
      for point in region_w:each_point() do
         local path = _radiant.sim.adjacency.query_sync(start_point, point, nav_grid_id)

         if not path then
            ladder_points_map:clear()
            break
         end
         for _, ladder_point in ipairs(path:get_points()) do
            ladder_point = Point3(ladder_point.x, ladder_point.y, ladder_point.z)
            ladder_points_map:add(ladder_point, ladder_point)
         end
      end
   else
      for point in region_w:each_point() do
         local path = _radiant.sim.adjacency.query_sync(start_point, point, nav_grid_id)

         if path then
            for _, ladder_point in ipairs(path:get_points()) do
               ladder_point = Point3(ladder_point.x, ladder_point.y, ladder_point.z)
               ladder_points_map:add(ladder_point, ladder_point)
            end
            break
         end
      end
   end

   for pt in ladder_points_map:each() do
      table.insert(ladder_points, pt)
   end

   if radiant.empty(ladder_points) then
      return nil
   end

   log:detail('need ladders at:')
   for _, p in ipairs(ladder_points) do
      log:detail('  %s', p)
   end
   return ladder_points
end

local function _wire_topology_paths_to_any_root(root_points, region_w, is_scaffolding, nav_grid_id)
   for _, root_point in ipairs(root_points) do
      local ladder_points = _wire_topology_paths_to_root(root_point, region_w, is_scaffolding, nav_grid_id)
      if ladder_points then
         return ladder_points
      end
   end
   return nil
end

function AceComputePlanJob:_process_chunk(piece, piece_origin, bc, root_points, chunk_node, mining, anti_scaffolding, reachability)
   local piece_id = piece:get_id()
   log:info('processing %s at %s', piece_id, radiant.entities.get_world_region(piece):get_bounds())

   local scaffolding_normal = nil
   local scaffolding_region_w = nil
   local anti_scaffolding_region_w = nil
   local support_region_w = nil
   local required_ladders = nil
   local scaffolding_id = nil
   local destination = piece:get_component('destination'):get_region():get()
   local size = destination:get_bounds():get_size()

   -- This is a volume, and MUST be unblocked.  Workers will need to walk on it!
   if size.x > 1 and size.z > 1 then
      if _is_blocked(piece, self._sv._nav_grid_id) then
         return false
      end
   end

   -- This is a floor-like thing, so *maybe* we can walk on it while constructing it?
   -- That would be preferred, since we would not have to use scaffolding.
   if size.y == 1 and not _is_blocked(piece, self._sv._nav_grid_id) then
      support_region_w = _compute_adjacent(piece, piece_origin)

      required_ladders = {}
      if not self._sv._terrain_roots[piece_id] and not _connected_to_any_root(root_points, support_region_w, false, self._sv._nav_grid_id) then
         log:info('floor not connected to root; finding topology path')
         required_ladders = _wire_topology_paths_to_any_root(root_points, support_region_w, false, self._sv._nav_grid_id)
      end
   elseif size.y <= 3 and (size.x == 1 or size.z == 1) then
      -- this is a short wall/column; if the area to one side is unblocked and standable, we can build it without scaffolding
      local non_scaffolding_region_w = _compute_non_scaffolding_region(piece, piece_origin, self._sv._nav_grid_id)
      if non_scaffolding_region_w then
         required_ladders = {}
         if not self._sv._terrain_roots[piece_id] and not _connected_to_any_root(root_points, non_scaffolding_region_w, false, self._sv._nav_grid_id) then
            log:info('non-scaffolding standing region not connected to root; finding topology path')
            required_ladders = _wire_topology_paths_to_any_root(root_points, non_scaffolding_region_w, false, self._sv._nav_grid_id)
         end
      end
   end

   -- 'nil' required ladders means _wire_topology_paths failed (or we never got there), and so we need to find scaffolding.
   if required_ladders == nil then
      required_ladders = {}

      scaffolding_region_w, scaffolding_normal = _compute_scaffolding_region(piece, piece_origin, self._sv._nav_grid_id)
      if not scaffolding_region_w then
         return false
      end

      scaffolding_id = bc:get_scaffolding_set():get_next_region_id()
      support_region_w = _compute_support(scaffolding_region_w)
      anti_scaffolding_region_w = _compute_anti_scaffolding(scaffolding_region_w, self._sv._nav_grid_id)

      if not self._sv._terrain_roots[piece_id] and not _connected_to_any_root(root_points, support_region_w, scaffolding_region_w ~= nil, self._sv._nav_grid_id) then
         log:info('not connected to root; finding topology path')
         required_ladders = _wire_topology_paths_to_any_root(root_points, support_region_w, scaffolding_region_w ~= nil, self._sv._nav_grid_id)
      end
   end

   if required_ladders == nil then
      return false
   end

   log:info('success; claiming chunk.')

   reachability:add_ladders(required_ladders)
   -- local terrain_region_w = _compute_mining_region(piece, piece_origin, self._sv._nav_grid_id)
   -- if not terrain_region_w:empty() then
   --    mining:add_terrain_region(terrain_region_w)
   --    self._sv._terrain_region_w:add_region(terrain_region_w)
   -- end

   -- Update envelope region.
   if scaffolding_region_w ~= nil then
      self._sv._envelope_w:add_region(scaffolding_region_w)
   end
   for _, pt_w in ipairs(required_ladders) do
      self._sv._envelope_w:add_point(pt_w)
   end

   log:info('adding chunk for %s with data: %s, %s, %s, %s, %s, %s',
         piece_id, self._sv._piece_2_structures[piece_id], destination:get_bounds(), radiant.entities.get_world_grid_location(piece),
         tostring(scaffolding_id), scaffolding_region_w and scaffolding_region_w:get_bounds() or 'no scaffolding', tostring(scaffolding_normal))
   chunk_node:add_chunk(
      piece_id,
      self._sv._piece_2_structures[piece_id],
      destination:duplicate(),
      radiant.entities.get_world_grid_location(piece),
      scaffolding_id,
      scaffolding_region_w,
      scaffolding_normal
   )

   anti_scaffolding:add_region(scaffolding_id, anti_scaffolding_region_w)
   return true
end

function AceComputePlanJob:_process_fixture(piece, piece_origin, root_points, fixture, reachability)
   -- A fixture only has to have one of its adjacent _points_ be reachable and standable.
   -- So, no need for scaffolding, or even the requirement that we be able to walk over the thing.
   local piece_id = piece:get_id()
   log:info ('processing fixture %s (%s) at %s', piece_id, piece:get('stonehearth:build2:building_piece'):get_data():get_uri(), radiant.entities.get_world_region(piece):get_bounds())

   local support_region_w = nil
   local required_ladders = {}

   local skip = true
   local bot_w, top_w, normal
   if _requires_ladder(piece, piece_origin, self._sv._nav_grid_id) then
      bot_w, top_w, normal = _compute_fixture_ladder_region(piece, piece_origin, self._sv._nav_grid_id)
      if bot_w then
         support_region_w = Region3(Cube3(bot_w, bot_w + Point3(1, 1, 1)))
         skip = false
      end
   else
      support_region_w = _compute_adjacent(piece, piece_origin)
      skip = false
   end

   if skip then
      return false
   end

   log:info('%s fixture setting up ladder %s %s %s with support %s', piece_id, tostring(bot_w), tostring(top_w), tostring(normal), support_region_w:get_bounds())
   if not _connected_to_any_root(root_points, support_region_w, false, self._sv._nav_grid_id) then
      log:info('not connected to root; finding topology path')
      required_ladders = _wire_topology_paths_to_any_root(root_points, support_region_w, false, self._sv._nav_grid_id)
   end
   if required_ladders == nil then
      log:info('could not find a ladder for fixture %s', piece_id)
      return false
   end

   log:info('success; claiming fixture.')

   reachability:add_ladders(required_ladders)

   if top_w then
      reachability:add_ladders({top_w})
   end

   fixture:add_fixture(
      piece:get_id(),
      piece:get('stonehearth:build2:building_piece'):get_data()
   )
   return true
end

return AceComputePlanJob
