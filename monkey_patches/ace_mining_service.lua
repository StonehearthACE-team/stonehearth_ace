local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local LandmarkLib = require 'stonehearth.lib.landmark.landmark_lib'
local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('mining')

local MiningService = require 'stonehearth.services.server.mining.mining_service'
local AceMiningService = class()

----------------------------------------------------------------------------
-- Use the dig_* methods to let the mining service manage the zones for you.
-- Use the create_mining_zone, add_region_to_zone, and merge_zones methods
-- to explicitly manage the zones yourself.
----------------------------------------------------------------------------

-- Dig an arbitary region.
-- Region is defined in world space.
-- purpose is optional and defaults to constants.mining.purpose.MINING
function AceMiningService:dig_region(player_id, region, purpose, options)
   local disable_merging = options and options.disable_merging
   local bid = options and options.bid

   -- using town as a proxy for the eventual player object
   local town = stonehearth.town:get_town(player_id)
   local existing_zones = town:get_mining_zones()

   -- remove region outside terrain bounds and remove all bedrock
   region = LandmarkLib.intersect_with_terrain_bounds_and_remove_bedrock(region)

   -- shrink wrap the region to the bounds of the intersected terrain
   local terrain_intersection = radiant.terrain.intersect_region(region)
   local terrain_bounds = terrain_intersection:get_bounds()
   region = region:intersect_cube(terrain_bounds)

   -- don't overlap any existing zones
   -- WARNING: this can cause disjoint regions if we choose not to merge with the overlapped zone
   region = self:_subtract_existing_zones(region, existing_zones)

   if region:empty() then
      return nil
   end

   if self._enable_insta_mine then
      self:insta_mine(region)
      return nil
   end

   local mergable_zones = {}
   if not disable_merging then
      local adjacent_zones = self:_get_adjacent_zones(region, existing_zones)
      local ordered_zones = self:_get_zones_by_descending_volume(adjacent_zones)

      -- auto-merge anything within another zone's bounding box
      -- merged areas will be subtracted from region
      local largest_merged_zone = self:_bounding_box_merge(region, ordered_zones)
      if region:empty() then
         return largest_merged_zone
      end

      mergable_zones = self:_get_mergable_zones(region, adjacent_zones, purpose, bid)
   end

   local selected_zone = self:_choose_merge_survivor(mergable_zones)
   selected_zone = self:_validate_merge_survivor(selected_zone, region)

   if selected_zone then
      -- remove the surviving zone from the merge list
      mergable_zones[selected_zone:get_id()] = nil
   else
      -- no adjacent or overlapping zone exists, so create a new one
      selected_zone = self:create_mining_zone(player_id, purpose, options and options.start_suspended)
      if bid then
         selected_zone:add_component('stonehearth:mining_zone'):set_bid(bid)
      end
      town:add_mining_zone(selected_zone)
   end

   self:add_region_to_zone(selected_zone, region)

   -- merge the other zones into the surviving zone and destroy them
   for _, zone in pairs(mergable_zones) do
      if self:_allow_merge(selected_zone, zone) then
         self:merge_zones(selected_zone, zone)
      end
   end

   selected_zone:add_component('stonehearth:mining_zone'):get_region():modify(function(cursor)
         cursor:optimize('MiningService:dig_region')
      end)

   return selected_zone
end

-- ACE: add building id restriction for merging (if nil, match only nil [i.e., not part of a building]; otherwise match specific building id)
function AceMiningService:_get_mergable_zones(region, adjacent_zones, purpose, bid)
   local mergable_zones = {}

   -- find all the existing mining zones that are adjacent or overlap the new region
   for id, zone in pairs(adjacent_zones) do
      local location = radiant.entities.get_world_grid_location(zone)
      local mining_zone_component = zone:add_component('stonehearth:mining_zone')
      if mining_zone_component:get_purpose() == purpose and mining_zone_component:get_bid() == bid then
         local existing_region = mining_zone_component:get_region():get()
         local region_local = region:translated(-location)

         if self:_allow_merge_region(region_local, existing_region) then
            mergable_zones[id] = zone
         end
      end
   end

   return mergable_zones
end

-- ACE: vertically optimize mining region
function AceMiningService:_bounding_box_merge(region, ordered_zones)
   local largest_merged_zone = nil

   for _, zone in ipairs(ordered_zones) do
      local location = radiant.entities.get_world_grid_location(zone)
      local boxed_region = zone:add_component('stonehearth:mining_zone'):get_region()
      local bounding_box = boxed_region:get():get_bounds():translated(location)
      local intersection = region:intersect_cube(bounding_box)

      if not intersection:empty() then
         region:subtract_cube(bounding_box)

         intersection:translate(-location)
         boxed_region:modify(function(cursor)
               cursor:copy_region(csg_lib.get_vertically_optimized_region(cursor, intersection))
               -- unnecessary optimize
               --cursor:optimize('mining service:_bounding_box_merge')
            end)

         if not largest_merged_zone then
            largest_merged_zone = zone
         end
      end
   end

   return largest_merged_zone
end

-- ACE: vertically optimize mining region
-- Explicitly add a region to a mining zone.
function AceMiningService:add_region_to_zone(mining_zone, region)
   if not region or region:empty() then
      return
   end

   local mining_zone_component = mining_zone:add_component('stonehearth:mining_zone')
   local boxed_region = mining_zone_component:get_region()
   local location

   if boxed_region:get():empty() then
      location = region:get_bounds().min
      radiant.terrain.place_entity_at_exact_location(mining_zone, location)
   else
      location = radiant.entities.get_world_grid_location(mining_zone)
   end

   boxed_region:modify(function(cursor)
         -- could avoid a region copy if we're willing to modify the input region
         local local_region = region:translated(-location)
         cursor:copy_region(csg_lib.get_vertically_optimized_region(cursor, local_region))
      end)
end

-- ACE: vertically optimize mining region
-- Merges zone2 into zone1, and destroys zone2.
function AceMiningService:merge_zones(zone1, zone2)
   local boxed_region1 = zone1:add_component('stonehearth:mining_zone'):get_region()
   local boxed_region2 = zone2:add_component('stonehearth:mining_zone'):get_region()
   local location1 = radiant.entities.get_world_grid_location(zone1)
   local location2 = radiant.entities.get_world_grid_location(zone2)

   -- move region2 into the local space of region1
   local translation = location2 - location1
   local region2 = boxed_region2:get():translated(translation)
   boxed_region1:modify(function(region1)
         region1:copy_region(csg_lib.get_vertically_optimized_region(region1, region2))
      end)

   radiant.entities.destroy_entity(zone2)
end

AceMiningService._ace_old_get_reachable_region = MiningService.get_reachable_region
function AceMiningService:get_reachable_region(location, worker_location)
   local region = self:_ace_old_get_reachable_region(location)

   local bounds = region:get_bounds()
   local max_y = bounds.max.y
   local min_y = bounds.min.y

   -- also include reachable blocks directly above; this is important for building a ladder to reach the top of the mining region
   if max_y > location.y then
      local cube = Cube3(location)
      cube.max.y = max_y
      region:add_cube(cube)
   end

   -- also remove any blocks that are directly below the worker location
   if worker_location and worker_location.y > min_y then
      local cube = Cube3(worker_location)
      cube.min.y = min_y
      cube.max.y = worker_location.y
      region:subtract_cube(cube)
   end

   -- TODO: also include diagonal blocks below (this gets clipped if terrain is on either side)?
   return region
end

-- Chooses the best point to mine when standing on from.
function AceMiningService:get_block_to_mine(from, mining_zone, worker_location, log_debug)
   local location = radiant.entities.get_world_grid_location(mining_zone)
   local destination_component = mining_zone:add_component('destination')
   local destination_region = destination_component:get_region():get()
   local reserved_region = destination_component:get_reserved():get()

   -- local mining_zone_component = mining_zone:get_component('stonehearth:mining_zone')
   -- local unsupported_region = mining_zone_component:get_unsupported()
   -- local supported_destination_region = unsupported_region:empty() and destination_region or (destination_region - unsupported_region)
   -- if supported_destination_region:empty() then
   --    -- unsupported is non-empty if supported destination is empty, because otherwise the mining zone would no longer exist
   --    local unsupported_region, distance = mining_zone_component:get_next_unsupported_bucket()
   --    if unsupported_region then
   --       log:debug('only considering mining unsupported blocks %s from support', distance)
   --       supported_destination_region = unsupported_region
   --    else
   --       return nil, nil
   --    end
   -- end

   -- get the reachable region in local coordinates to the zone
   local from_local = from - location
   local reachable_region = self:get_reachable_region(from_local, worker_location - location)
   local eligible_region = reachable_region - reserved_region
   local eligible_destination_region = eligible_region:intersect_region(destination_region)
   local block = nil
   local cubes = {}
   for cube in eligible_destination_region:each_cube() do
      table.insert(cubes, cube)
   end

   while not eligible_destination_region:empty() do
      local distance
      local closest

      -- pick any closest point in the region
      for cube in eligible_destination_region:each_cube() do
         local point = cube:get_closest_point(from_local)
         local dist = point:distance_to(from_local)
         if not distance or dist < distance then
            closest = point
            distance = dist
         end
      end

      -- subtract one to get terrain coordinates from closest and convert to world coordinates
      block = closest + location
      if log_debug then
         log:debug('considering mining block %s from %s distance...', block, distance)
      end

      -- double check that we're not mining a block directly *below us only*
      -- we actually need to do this check on the actual worker location, not the adjacent location
      -- if not (block.x ~= worker_location.x or block.z ~= worker_location.z or block.y >= worker_location.y) then
      --    log:error('assert error on worker location %s (from %s) and block %s; cubes: %s', worker_location, from, block, radiant.util.table_tostring(cubes))
      -- end
      assert(block.x ~= worker_location.x or block.z ~= worker_location.z or block.y >= worker_location.y)

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
      eligible_destination_region:subtract_point(closest)
   end

   log:debug('no blocks to mine from %s: reachable area = %s, eligible_destination_region = %s', from, reachable_region:get_area(), radiant.util.table_tostring(cubes))
   return nil, nil
end

-- Returns a region containing the block and all blocks that support it.
-- Currently just the blocks below the block, but could be useful when trying to
-- clear out unsupported floors.
function AceMiningService:get_reserved_region_for_block(block, from, mining_zone)
   local location = radiant.entities.get_world_grid_location(mining_zone)
   local mining_zone_component = mining_zone:add_component('stonehearth:mining_zone')
   local zone_region = mining_zone_component:get_region():get()
   -- moving these to local coordinates
   local block = block - location

   local cube = Cube3(block, block + Point3.one)
   -- reserve the column to the bottom of the zone
   cube.min.y = zone_region:get_bounds().min.y

   local proposed_region = Region3(cube)
   local reserved_region = zone_region:intersect_region(proposed_region)

   -- ACE: exclude unsupported blocks (except for the selected block)
   local unsupported_region = mining_zone_component:get_unsupported()
   if not unsupported_region then
      reserved_region:subtract_region(unsupported_region)
      reserved_region:add_point(block)
   end

   -- by convention, all input and output values in the mining service are in world coordiantes
   reserved_region:translate(location)

   -- ACE: also add the block that will be mined from, so it gets removed from adjacency
   -- and other miners don't try to path to the same spot where blocks are already reserved
   reserved_region:add_point(from)
   return reserved_region
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

-- don't remove one point a time; remove the whole thing at once
function AceMiningService:insta_mine(region)
   local terrain_region = radiant.terrain.intersect_region(region)

   -- check all adjacent areas for water regions
   -- if there's a single water region, create a new water region in this mining region at that height
   -- then merge it into that other region
   -- if there are multiple regions, let them handle it themselves, it could be complicated
   stonehearth.hydrology:auto_fill_water_region(terrain_region, function(waters)
         radiant.terrain.subtract_region(terrain_region)

         self._mined_region:add_region(terrain_region)
         self._mined_region:optimize_changed_tiles('MiningService:_add_to_mined_region')

         -- and then update interior on a point-by-point basis
         for point in terrain_region:each_point() do
            self:_update_interior_region(point)
         end

         return true
      end)
end

return AceMiningService
