local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local AdjacencyFlags = _radiant.csg.AdjacencyFlags

local Chunk = require 'stonehearth.components.building2.plan.chunk'
local AceChunk = class()

function AceChunk:get_build_height()
   return self._sv._build_height
end

AceChunk._ace_old_set_data = Chunk.set_data
function AceChunk:set_data(mode, owning_structure, color_region_l, allow_unrestricted_building, allow_vertical_adjacency, wait_for_updates)
   self:_ace_old_set_data(mode, owning_structure, color_region_l, allow_unrestricted_building, allow_vertical_adjacency, wait_for_updates)

   -- ACE: if we're building a large volume, not just a column/wall, only build one layer at a time;
   -- that way we can stand in it and build within cramped areas
   local size = self._sv._allowed_mask:get_size()
   if size.x > 1 and size.z > 1 then
      self._sv._build_height = 1
      self._sv._allowed_mask.max.y = self._sv._allowed_mask.min.y + 1
   end
end

function AceChunk:get_owning_structure()
   return self._sv._owning_structure
end

function AceChunk:get_owning_building()
   local structure = self._sv._owning_structure
   local structure_comp = structure and structure:get_component('stonehearth:build2:structure')
   return structure_comp and structure_comp:get_owning_building()
end

-- ACE BUILD HEIGHT
function AceChunk:_get_projected_work_blocks()
   if self:_build_from_base() then
      local scaffolding_c = self._entity:get('stonehearth:build2:scaffolding_region')
      if scaffolding_c then
         local r = scaffolding_c:get_final()
         if r:intersects_region(self._sv._owning_structure:get('stonehearth:build2:structure'):get_clip_mask():translated(-self._sv._structure_offset)) then
            local origin = radiant.entities.get_world_grid_location(self._entity)
            --[[self._bid = stonehearth.debug_shapes:show_box(r:translated(origin), Color4(0, 0, 255, 255), nil, {
                  box_id = self._bid
               })]]
            return Region3.zero:duplicate()
         end
      end
   end

   -- Take the remainder, and intersect against the available_mask...
   local all_region = self._sv._remaining_l:intersect_cube(self._sv._allowed_mask)
   local min_y = all_region:get_bounds().min.y

   if not self._sv._allow_unrestricted_building then
      local all_region_bounds = all_region:get_bounds()
      -- If we have an allowed-mask (basically, if we're not scaffolding), then
      -- if the remaining allowed region is the rest of the chunk, we're going to make the
      -- origin of this thing 'build_height' from the top, instead of at the bottom of
      -- the allowed region (so that we don't build more scaffolding than we need to.)
      if all_region_bounds.max.y == self._sv._remaining_l:get_bounds().max.y then
         min_y = math.max(self._sv._material_region_l:get_bounds().min.y - 1, all_region_bounds.max.y - self._sv._build_height)
      end
   end

   -- project onto xz..
   all_region = all_region:project_onto_xz_plane()

   -- lift 1, putting this at the base.
   all_region = all_region:lift(min_y, min_y + 1)

   return all_region
end

-- We're wall-like: many voxels "wide" and "tall", but exactly one "deep".
function AceChunk:_update_adjacent_for_wall()
   local normal, perp = self:_get_normal()
   assert(normal)
   local adjacent

   local origin = radiant.entities.get_world_grid_location(self._entity)
   local all_region = self:_get_projected_work_blocks()

   if all_region:empty() then
      adjacent = Region3.zero
   else
      -- Now, fan out.
      adjacent = all_region:translated(normal) + all_region:translated(-normal)
         + all_region:translated(perp) + all_region:translated(-perp)

      -- "Grommit Requirement" (see comment in volume adjacent)
      adjacent:add_region(adjacent:translated(Point3(0, 1, 0)) + adjacent:translated(Point3(0, 2, 0)))

      -- ACE: also add regions below to allow for building upwards (from the side)
      -- ACE BUILD HEIGHT
      --adjacent:add_region(adjacent:translated(Point3(0, -1, 0)) + adjacent:translated(Point3(0, -2, 0)))

      if not self:is_solid() then
         adjacent:add_region(all_region)
      end
   end

   assert(adjacent:get_bounds():get_size().y <= 3) -- 5
   self._dst:get_adjacent():modify(function(cursor)
         cursor:copy_region(adjacent)
         cursor:subtract_region(self._dst:get_reserved():get())
      end)
end

-- if the original full mask is specified, compare the slice of it at the current build mask level
function AceChunk:_is_cur_layer_partially_built()
   local remaining_slice = self._sv._remaining_l:intersect_cube(self._sv._allowed_mask)
   return remaining_slice:get_area() < self._sv._allowed_mask:get_area()
end

function AceChunk:_update_adjacent_for_volume()
   local bottom = self._sv._remaining_l:get_bounds().min.y
   -- In the case of chunks that need to wait before advertising a new destination region
   -- (basically anything that has scaffolding), return if we're waiting.
   if bottom ~= self._sv._last_bottom and self._sv._wait_for_updates then
      if not self._sv._waiting_for_update then
         self._sv._waiting_for_update = true
         -- Clear the adjacent as well, just to be really clear we aren't a destination.
         self._dst:get_adjacent():modify(function(cursor)
               cursor:clear()
            end)
      end
      return
   end

   local dst_rgn = self._dst:get_region():get()
   if dst_rgn:get_area() == 0 then
      self._dst:get_adjacent():modify(function(cursor)
         cursor:clear()
      end)
      return
   end

   local not_solid = not self:is_solid()
   local build_from_base = self:_build_from_base()
   local can_build_inside = self._sv._build_height == 1 and not self:_is_cur_layer_partially_built()

   local adjacency_flags = AdjacencyFlags.ALL_EDGES
   if not_solid or can_build_inside then
      adjacency_flags = adjacency_flags + AdjacencyFlags.CENTER
   end

   local origin = radiant.entities.get_world_grid_location(self._entity)

   if build_from_base then
      local desired_bounds = self._sv._material_region_l:get_bounds()
      -- If we're building from the base, then let our destination be forever the
      -- bottom layer OF THE ORIGINATING STRUCTURE.  Use with care....

      -- TODO: these bits (minus the 'remaining' bits) are constant; pre-calculate once?
      dst_rgn = self._sv._owning_structure:get('stonehearth:build2:structure')
                                          :get_desired_shape_region():peel(Point3(0, 1, 0))
      dst_rgn:subtract_region(self._sv._owning_structure:get('stonehearth:build2:structure'):get_clip_mask())

      if dst_rgn:get_area() == 0 then
         -- We're not ready to build yet, because of the clip mask.  Zero-out our adjacency.
         self._dst:get_adjacent():modify(function(cursor)
            cursor:clear()
         end)
         return
      end

      dst_rgn = dst_rgn:translated(-self._sv._structure_offset)
      local dst_min_y = dst_rgn:get_bounds().min.y

      -- Mask out the part that this chunk is responsible for.
      dst_rgn = dst_rgn:intersect_cube(Cube3(
         Point3(desired_bounds.min.x, dst_min_y, desired_bounds.min.z),
         Point3(desired_bounds.max.x, desired_bounds.max.y, desired_bounds.max.z)))

      -- Further mask out the parts of the destination that have completed columns.
      local remaining_bounds = self._sv._remaining_l:get_bounds()
      local completed_mask = Cube3(
         Point3(remaining_bounds.min.x, dst_min_y, remaining_bounds.min.z),
         Point3(remaining_bounds.max.x, desired_bounds.max.y, remaining_bounds.max.z))

      dst_rgn = dst_rgn:intersect_cube(completed_mask)
   end

   local adjacent = dst_rgn:get_adjacent(adjacency_flags)

   -- Allow hearthlings to build 2 below!  Ask Chris if you want the dirty details,
   -- but this basically means 'if you can reach a structure to walk on it, you should
   -- also be able to reach down to build that thing'.  Call it the Grommit Requirement.
   adjacent:add_region(adjacent:translated(Point3(0, 1, 0)) + adjacent:translated(Point3(0, 2, 0)))

   -- Remove any bits we might be standing on.
   if not self._sv._allow_vertical_adjacency and not_solid then
      adjacent:subtract_region(self._sv._material_region_l:extruded('y', 0, 1))
   end

   -- Remove parts of the adjacent region which overlap the fabrication region.
   -- Otherwise we get weird behavior where one worker can build a block right
   -- on top of where another is standing to build another block, or workers
   -- can build blocks to hoist themselves up to otherwise unreachable spaces,
   -- getting stuck in the process.
   if not build_from_base and not can_build_inside then
      -- Building from base cannot possibly require this (dst never overlaps!)
      adjacent:subtract_region(dst_rgn)
   end

   -- Don't allow our adjacent to overlap with other chunks!
   -- Otherwise, the hearthlings constantly walk onto other things that are in the process of
   -- being completed, stranding themselves like _idiots_.
   local overlapping_chunks = radiant.terrain.get_entities_in_cube(adjacent:get_bounds():translated(origin), function(e)
         return e:get_uri() == 'stonehearth:build2:entities:chunk'
            and e:get_id() ~= self._entity:get_id()
            and e:get('stonehearth:build2:chunk'):is_solid()
            and not e:get_component('stonehearth:build2:scaffolding_region')
      end)

   for _, chunk in pairs(overlapping_chunks) do
      adjacent:subtract_cube(radiant.entities.get_world_bounds(chunk):translated(-origin))
   end

   if self._sv._paused then
      self._sv._saved_adjacency = adjacent
   else
      self._dst:get_adjacent():modify(function(cursor)
         cursor:copy_region(adjacent)
      end)
   end
end

return AceChunk
