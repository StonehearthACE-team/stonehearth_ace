local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('mining')

local MiningService = require 'stonehearth.services.server.mining.mining_service'
local AceMiningService = class()

-- also include reachable blocks directly above; this is important for building a ladder to reach the top of the mining region
AceMiningService._ace_old_get_reachable_region = MiningService.get_reachable_region
function AceMiningService:get_reachable_region(location)
   local region = self:_ace_old_get_reachable_region(location)
   local cube = Cube3(location)
   cube.max.y = region:get_bounds().max.y
   region:add_cube(cube)
   return region
end

-- Chooses the best point to mine when standing on from.
function AceMiningService:get_block_to_mine(from, mining_zone, log_debug)
   local location = radiant.entities.get_world_grid_location(mining_zone)
   local destination_component = mining_zone:add_component('destination')
   local destination_region = destination_component:get_region():get()
   local reserved_region = destination_component:get_reserved():get()

   -- get the reachable region in local coordinates to the zone
   local reachable_region = self:get_reachable_region(from - location)
   local eligible_region = reachable_region - reserved_region
   local eligible_destination_region = eligible_region:intersect_region(destination_region)
   local block = nil

   if log_debug then
      log:debug('considering mining in %s eligible_destination_region from %s with bounds %s and area %s...',
               mining_zone,
               from,
               eligible_destination_region:get_bounds(),
               eligible_destination_region:get_area())
   end

   while not eligible_destination_region:empty() do
      local max = eligible_destination_region:get_rect(0).min

      -- pick any highest point in the region
      for cube in eligible_destination_region:each_cube() do
         if cube.max.y > max.y then
            max = cube.max
         end
      end

      -- subtract one to get terrain coordinates from max and convert to world coordinates
      block = max - Point3.one + location
      if log_debug then
         log:debug('considering mining block %s...', block)
      end

      -- double check that we're not mining a block directly *below us only*
      assert(block.x ~= from.x or block.z ~= from.z or block.y > from.y)

      -- check if our current location is in the adjacent for the block
      local poi_adjacent = self:get_adjacent_for_destination_block(block)
      if poi_adjacent:contains(from) then
         if log_debug then
            log:debug('poi_adjacent %s contains %s!', poi_adjacent:get_bounds(), from)
         end
         -- check if the we can reserve the dependent blocks
         local reserved_region_for_block = self:get_reserved_region_for_block(block, from, mining_zone)
         local temp = reserved_region_for_block:translated(-location)

         if not temp:intersects_region(reserved_region) then
            return block, reserved_region_for_block
         end
      end

      -- look for another block
      eligible_destination_region:subtract_point(block - location)
   end

   return nil, nil
end

-- ACE: update to allow mining blocks directly above
-- Return all the locations that can reach the block at point.
-- Keep in sync with get_adjacent_for_destination_region or delegate to it.
function AceMiningService:get_adjacent_for_destination_block(point)
   -- create a cube that bounds the adjacent region
   local adjacent_bounds = Cube3(point):inflated(Point3(1, 0, 1))
   adjacent_bounds.min.y = point.y - self._max_reach_up
   adjacent_bounds.max.y = point.y + self._max_reach_down + 1

   -- terrain intersection is expensive in an inner loop, so make one call to grab the working terrain region
   local terrain_region = radiant.terrain.intersect_cube(adjacent_bounds)
   terrain_region:set_tag(0)

   local adjacent_region = Region3()
   local top_blocked = terrain_region:contains(point + Point3.unit_y)
   local bottom_blocked = terrain_region:contains(point - Point3.unit_y)

   for _, direction in ipairs(csg_lib.XZ_DIRECTIONS) do
      local adjacent_point = point + direction
      local cube = Cube3(adjacent_point)

      if not top_blocked then
         cube.max.y = adjacent_bounds.max.y
      end

      if not bottom_blocked then
         cube.min.y = adjacent_bounds.min.y
      else
         -- technically all blocks above the proposed adjacent should not be blocked
         -- don't bother to enforce this right now, since it won't affect gameplay
         local side_blocked = terrain_region:contains(adjacent_point)
         if not side_blocked then
            cube.min.y = adjacent_bounds.min.y
         end
      end

      adjacent_region:add_unique_cube(cube)
   end

   -- ACE: add below
   local below = Cube3(point)
   below.min.y = adjacent_bounds.min.y
   adjacent_region:add_unique_cube(below)

   adjacent_region:subtract_region(terrain_region)

   return adjacent_region
end

-- ACE: update to allow mining blocks directly above
-- Keep in sync with get_adjacent_for_destination_block.
function AceMiningService:get_adjacent_for_destination_region(region)
   local max_reach = math.max(self._max_reach_up, self._max_reach_down)
   local working_volume = region:get_bounds():inflated(Point3(1, max_reach, 1))
   local terrain_region = radiant.terrain.intersect_cube(working_volume)

   local adjacent_region = Region3()
   local above = region:translated(Point3.unit_y)
   -- remove blocks whose tops are blocked
   above:subtract_region(terrain_region)

   for _, direction in ipairs(csg_lib.XZ_DIRECTIONS) do
      local temp = above:translated(direction)
      -- -1 on MAX_REACH_DOWN because we're already 1 block above
      -- As an optimization, just omit the call if the extrusion doesn't change the shape
      if self._max_reach_down > 1 then
         temp = temp:extruded('y', 0, self._max_reach_down-1)
      end
      adjacent_region:add_region(temp)
   end

   -- ACE: add in blocks directly below the region, since we can now mine from below
   local below = region:translated(-Point3.unit_y)
   below:subtract_region(terrain_region)
   below = below:extruded('y', self._max_reach_up - 2, 0)
   adjacent_region:add_region(below)

   for _, direction in ipairs(csg_lib.XZ_DIRECTIONS) do
      -- technically all blocks above the proposed adjacent should not be blocked
      -- don't bother to enforce this right now, since it won't affect gameplay
      local temp = region:translated(direction)
      -- remove blocks whose side is blocked in this direction
      temp:subtract_region(terrain_region)
      temp = temp:extruded('y', self._max_reach_up - 1, 0)
      adjacent_region:add_region(temp)
   end

   -- remove adjacents blocked by terrain
   adjacent_region:subtract_region(terrain_region)
   return adjacent_region
end

return AceMiningService
