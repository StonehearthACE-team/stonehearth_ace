local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local BuildingPieceDependenciesJob = require 'stonehearth.components.building2.plan.jobs.building_piece_dependencies_job'
local AceBuildingPieceDependenciesJob = class()

local log = radiant.log.create_logger('build.building_piece_dependencies_job')

AceBuildingPieceDependenciesJob._ace_old_create = BuildingPieceDependenciesJob.create
function AceBuildingPieceDependenciesJob:create(job_data)
   self:_ace_old_create(job_data)
   self._sv._insert_craft_requests = job_data.insert_craft_requests
   self._sv._terrain_roots = job_data.terrain_roots
   self._sv._contiguous_terrain_regions = job_data.contiguous_terrain_regions
   self._sv._terrain_adjacencies = job_data.terrain_adjacencies
   self._sv._terrain_cutout = job_data.terrain_cutout
end

AceBuildingPieceDependenciesJob._ace_old_destroy = BuildingPieceDependenciesJob.__user_destroy
function AceBuildingPieceDependenciesJob:destroy()
   self:_ace_old_destroy()
   self._sv._insert_craft_requests = nil
   self._sv._terrain_roots = {}
   self._sv._contiguous_terrain_regions = {}
   self._sv._terrain_adjacencies = {}
   self._sv._terrain_cutout = nil
end

AceBuildingPieceDependenciesJob._ace_old_get_results = BuildingPieceDependenciesJob.get_results
function AceBuildingPieceDependenciesJob:get_results()
   local result = self:_ace_old_get_results()
   result.insert_craft_requests = self._sv._insert_craft_requests
   result.terrain_roots = self._sv._terrain_roots
   result.contiguous_terrain_regions = self._sv._contiguous_terrain_regions
   result.terrain_cutout = self._sv._terrain_cutout
   return result
end

function AceBuildingPieceDependenciesJob:plan_init()
   local piece_inverse_dependencies = self._sv._piece_inverse_dependencies
   local piece_dependencies = self._sv._piece_dependencies
   local terrain_pieces = {}
   local non_terrain_pieces = {}

   for piece_id, piece in pairs(self._sv._building_pieces) do
      local data = piece:get('stonehearth:build2:building_piece'):get_data()
      if data and data.in_terrain then
         terrain_pieces[piece_id] = piece
      else
         non_terrain_pieces[piece_id] = piece
      end

      piece_inverse_dependencies[piece_id] = {}
      piece_dependencies[piece_id] = {}
   end

   -- ACE: make all pieces outside terrain region depend on all pieces inside terrain region
   for piece_id, piece in pairs(non_terrain_pieces) do
      for terrain_piece_id, terrain_piece in pairs(terrain_pieces) do
         self:_add_dependency(piece_dependencies, piece_inverse_dependencies, terrain_piece_id, terrain_piece, piece_id, piece)
      end
   end

   self:incstage()
end

-- TODO: this completes in one go.  It's actually fairly fast (basilica completes in 300ms), but not
-- fast enough to not cause hitches!  It's gross to get this yieldable, though (basically need a
-- state machine.)  So, do that, just not right now....
-- ACE: handle terrain being a horizontal adjacency (prioritize building these pieces first)
function AceBuildingPieceDependenciesJob:compute_dependencies()
   log:info('compute_dependencies')

   -- Hitting an sv over and over and over again involves some small meta-table costs, so given
   -- how hot this function is, let's cache.
   local piece_inverse_dependencies = self._sv._piece_inverse_dependencies
   local piece_dependencies = self._sv._piece_dependencies
   local piece_adjacencies = self._sv._piece_adjacencies
   local terrain_adjacencies = self._sv._terrain_adjacencies

   local nonzero_terrain_adjacencies = {}
   for id, count in pairs(terrain_adjacencies) do
      if count > 0 then
         nonzero_terrain_adjacencies[id] = count
      end
   end
   log:debug('terrain adjacencies: %s', radiant.util.table_tostring(nonzero_terrain_adjacencies))

   -- We now have every single spatial adjacency for every structure in the building,
   -- including terrain dependencies.  Start from the roots and grow the dep tree.
   local function wire_dependencies(traverse_mask, path_mask, starts, filter_fn, lowest_first)
      local explored_dependencies = {}

      local function wire_dependency(building_pieces)
         local next_building_pieces = {}
         for piece_id, piece in pairs(building_pieces) do
            local adjs = piece_adjacencies[piece_id]

            local new_deps = starts[piece_id] and true or false

            if lowest_first then
               -- This path is used exclusively for horizontal dependencies.  We sort
               -- all horizontal adjacencies, and look from the bottom up for something
               -- we can claim.  This avoids weird issues where a tall piece can depend
               -- on something near its top, despite also being connected to things on the
               -- bottom, which is far more logical given that hearthlings build from
               -- the ground up.  This helps make building construction smoother and more
               -- logical.
               local all_adjs = {}
               for _, offset in ipairs(path_mask) do
                  -- Is the direction we are considering valid for checking adjacencies?
                  for adj_id, adj in pairs(adjs:get(offset)) do
                     -- Nobody can depend on a fixture!  Fixtures that are to be placed
                     -- in locations that are cramped (and would therefore require a
                     -- dependency) will still be handled like regular pieces during
                     -- the actual plan processing.
                     if not adj:get('stonehearth:build2:building_piece'):is_fixture() then
                        table.insert(all_adjs, adj)
                     end
                  end
               end

               table.sort(all_adjs, function(a, b)
                     local a_min_y = radiant.entities.get_world_bounds(a).min.y
                     local b_min_y = radiant.entities.get_world_bounds(b).min.y
                     return a_min_y < b_min_y
                  end)

               for _, adj in ipairs(all_adjs) do
                  local adj_id = adj:get_id()
                  if filter_fn(piece_id, piece, adj_id) then
                     local result = self:_add_dependency(
                        piece_dependencies,
                        piece_inverse_dependencies,
                        adj_id, adj,
                        piece_id, piece)

                     if result then
                        log:detail(' %s depends on %s', piece_id, adj_id)
                        new_deps = true
                        -- Only record 1 such dependency.
                        break
                     end
                  end
               end
            else
               for _, offset in ipairs(path_mask) do
                  -- Is the direction we are considering valid for checking adjacencies?
                  for adj_id, adj in pairs(adjs:get(offset)) do
                     -- Nobody can depend on a fixture!  Fixtures that are to be placed
                     -- in locations that are cramped (and would therefore require a
                     -- dependency) will still be handled like regular pieces during
                     -- the actual plan processing.
                     if not adj:get('stonehearth:build2:building_piece'):is_fixture() then
                        if filter_fn(piece_id, piece, adj_id) then
                           local result = self:_add_dependency(
                              piece_dependencies,
                              piece_inverse_dependencies,
                              adj_id, adj,
                              piece_id, piece)

                           if result then
                              log:detail(' %s depends on %s', piece_id, adj_id)
                           end

                           -- Record if we found a new dep!
                           new_deps = new_deps or result
                        end
                     end
                  end
               end
            end

            for _, offset in ipairs(traverse_mask) do
               -- Is the direction valid for getting the next building_pieces?
               for adj_id, adj in pairs(adjs:get(offset)) do
                  -- Conditions on exploring an adjacent: it is not a start (root); and either
                  -- we've seen our own dependencies change, or that adjacent hasn't been explored.
                  -- This is done because we want to make sure we only re-explore old nodes if
                  -- necessary (it can easily be the case that a previously-explored node needs
                  -- to be explored again, in case it can now vertically depend on a node that
                  -- was just found to have a path to a root.)
                  if not starts[adj_id] and (new_deps or not explored_dependencies[adj_id]) then
                     explored_dependencies[adj_id] = true
                     next_building_pieces[adj_id] = adj
                  end
               end
            end
         end
         if next(next_building_pieces) then
            wire_dependency(next_building_pieces)
         end
      end

      for piece_id, piece in pairs(starts) do
         explored_dependencies[piece_id] = true
      end
      wire_dependency(starts)
   end

   local roots = radiant.shallow_copy(self._sv._roots)

   log:detail('roots:')
   local path_to_root = {}
   for id,  piece in pairs(roots) do
      log:detail(' %s', piece)
      path_to_root[id] = true

      self._debug_pieces[id] = stonehearth.debug_shapes:show_box(piece, Color4(255, 0, 255, 255), nil, {
         flag = 'debug_viz.building_plan_job',
         material = 'materials/voxel.material.json',
      })
   end

   local positive_vertical_offsets = { Point3(0, 1, 0) }
   local negative_vertical_offsets = { Point3(0, -1, 0) }
   local outward_offsets_only = { Point3(1, 0, 0), Point3(-1, 0, 0), Point3(0, 1, 0), Point3(0, 0, 1), Point3(0, 0, -1)}
   local horizontal_offsets = { Point3(1, 0, 0), Point3(-1, 0, 0), Point3(0, 0, 1), Point3(0, 0, -1) }

   -- I think this might be correct!  Starting from the roots of the building, we traverse in every direction
   -- _except_ 'down', looking for structural dependencies.  We do this first with vertical dependencies,
   -- unconditionally adding deps because we want a structure to depend on everything it rests upon.  Then we
   -- do this for horizontal dependencies, ignoring anything that already has a path to the root (a horizontal
   -- dependency should _only_ be used if nothing vertical is there to support the structure.)  Then, we look
   -- for negative vertical dependencies, traversing in all directions.  If we find one, we mark it as a potential
   -- new root (note that we erase previously-found roots as we find new ones that depend on the old ones).
   -- At the end of the loop, it is easy to see that every single structure that can reach the root via +vertical
   -- and horizontal movement is now wired, and that all direct -vertical deps are wired as well (with some now
   -- in the 'new_roots' table).  We copy the new roots to the roots table, and iterate again (so that we can now
   -- explore the sub-structures that grow out of the negative vertical dependencies.)

   local new_roots = {}

   -- Vertical offsets are a little funny; we want ALL paths to any roots (so that, for example, floors depend
   -- on both the columns and walls they rest on.)
   local function consider_vertical_dependency(piece_id, piece, adj_id)
      path_to_root[piece_id] = true

      local piece = self._sv._building_pieces[piece_id]
      local color = math.abs(radiant.math.hash(piece_id)) % 200

      if not self._debug_pieces[piece_id] then
         self._debug_pieces[piece_id] = stonehearth.debug_shapes:show_box(piece, Color4(0, 55 + color, 0, 255), nil, {
            flag = 'debug_viz.building_plan_job',
            material = 'materials/voxel.material.json',
         })
      end
      return true
   end

   local function consider_horizontal_dependency(piece_id, piece, adj_id)
      if not path_to_root[adj_id] then
         return false
      end
      if path_to_root[piece_id] then
         -- if there's a path to the root for this piece, check if there are fewer terrain adjacencies on the adjacent piece
         -- if so, we don't need to be dependent on it
         if terrain_adjacencies[adj_id] <= terrain_adjacencies[piece_id] then
            log:debug('%s (%s) has fewer terrain adjacencies than %s (%s), so %s does not need to depend on it',
                  adj_id, terrain_adjacencies[adj_id], piece_id, terrain_adjacencies[piece_id], piece_id)
            return false
         end
      end
      local piece = self._sv._building_pieces[piece_id]
      local color = math.abs(radiant.math.hash(piece_id)) % 200
      if not self._debug_pieces[piece_id] then
         self._debug_pieces[piece_id] = stonehearth.debug_shapes:show_box(piece, Color4(0, 0, 55 + color, 255), nil, {
            flag = 'debug_viz.building_plan_job',
            material = 'materials/voxel.material.json',
         })
      end
      path_to_root[piece_id] = true
      return true
   end

   local function consider_negative_vertical_dependency(piece_id, piece, adj_id)
      if not path_to_root[adj_id] or path_to_root[piece_id] then
         return false
      end
      local piece = self._sv._building_pieces[piece_id]
      local color = math.abs(radiant.math.hash(piece_id)) % 200
      if not self._debug_pieces[piece_id] then
         self._debug_pieces[piece_id] = stonehearth.debug_shapes:show_box(piece, Color4(55 + color, 0, 0, 255), nil, {
            flag = 'debug_viz.building_plan_job',
            material = 'materials/voxel.material.json',
         })
      end
      new_roots[adj_id] = nil
      new_roots[piece_id] = piece
      path_to_root[piece_id] = true
      return true
   end

   while next(roots) do
      log:detail('vertical offsets')
      wire_dependencies(outward_offsets_only, negative_vertical_offsets, roots, consider_vertical_dependency)

      log:detail('horizontal offsets')
      wire_dependencies(outward_offsets_only, horizontal_offsets, roots, consider_horizontal_dependency, true)

      log:detail('negative vertical offsets')
      wire_dependencies(BuildingPieceDependenciesJob.ALL_OFFSETS, positive_vertical_offsets, roots, consider_negative_vertical_dependency)
      roots = new_roots
      new_roots = {}
   end


   -- We used to signal failure here if we couldn't figure out any dependencies for a chunk.
   -- Instead, let's just continue on.  This will mean floating chunks, but also more
   -- buildable things.
   --[[
   local failed_pieces = {}
   for id, piece in pairs(self._sv._building_pieces) do
      if not piece:get('stonehearth:build2:building_piece'):is_fixture() then
         if radiant.empty(self._sv._piece_dependencies[id]) then
            if not self._sv._roots[id] and not self._sv._roof_like_pieces[id] then
               table.insert(failed_pieces, radiant.entities.get_world_region(piece))
            end
         end
      end
   end

   if not radiant.empty(failed_pieces) then
      self:signal_failure()
      self:set_failure_payload(failed_pieces)
      return
   end]]

   log:info('done compute_dependencies')

   self:incstage()
end

return AceBuildingPieceDependenciesJob
