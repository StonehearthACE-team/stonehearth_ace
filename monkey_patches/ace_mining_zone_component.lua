local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Rect2 = _radiant.csg.Rect2
local Cube3 = _radiant.csg.Cube3
local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3

local build_util = require 'stonehearth.lib.build_util'
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local landmark_lib = require 'stonehearth.lib.landmark.landmark_lib'

local log = radiant.log.create_logger('mining')

local MiningZoneComponent = require 'stonehearth.components.mining_zone.mining_zone_component'
local AceMiningZoneComponent = class()

local MAX_DESTINATION_DELTA_Y = 1

AceMiningZoneComponent._ace_old_destroy = MiningZoneComponent.__user_destroy
function AceMiningZoneComponent:destroy()
   self:_destroy_ladders()

   self:_ace_old_destroy()
end

function AceMiningZoneComponent:_destroy_ladders()
   if self._sv._ladder_handles then
      for _, lh in ipairs(self._sv._ladder_handles) do
         if lh:is_last_handle() then
            --lh:get_builder():destroy_immediately()
            local builder = lh:get_builder()
            -- hack to turn this into a user-teardown ladder handle
            builder._sv.user_extension_handle = lh
            local player_id = self._entity:get_player_id()
            if self._sv.bid then
               -- if it's part of a building, we need to automatically instantly destroy the ladders
               radiant.entities.destroy_entity(builder:get_ladder())
            elseif stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'auto_remove_mining_zone_ladders', true) then
               stonehearth.build:remove_ladder_command({player_id = player_id}, nil, builder:get_ladder())
            else
               builder:get_ladder():add_component('stonehearth:commands'):add_command('stonehearth:commands:remove_ladder')
            end
         else
            lh:destroy()
         end
      end
      self._sv._ladder_handles = nil
   end
end

function AceMiningZoneComponent:get_bid()
   return self._sv.bid
end

function AceMiningZoneComponent:set_bid(bid)
   self._sv.bid = bid
   self.__saved_variables:mark_changed()
   return self
end

function AceMiningZoneComponent:_on_region_changed()
   -- cache the region bounds.  force optimize before caching to make
   -- sure we absolutely have the minimal region.  not having the smallest
   -- region possible will have cascading performance problems down the
   -- line.
   self._sv.region:modify(function(cursor)
      cursor:set_tag(0)
      cursor:force_optimize('mining zone region changed')
      log:debug('mining zone contains %d cubes:', cursor:get_num_rects())
      for cube in cursor:each_cube() do
         log:debug('... %s', cube)
      end
   end)
   self.__saved_variables:mark_changed()

   -- update ladders
   if self._sv.region:get():get_bounds():get_size().y > 4 then
      self._sv._should_have_ladders = true
   end
   self:_update_ladder_regions()

   self:_update_unsupported()
   self:_update_destination()
   self:_update_designation()
end

function AceMiningZoneComponent:_update_unsupported()
   -- determine the bottom-most block at each x-z point
   -- keep track of all of those points that are unsupported
   -- we don't have to worry about terrain being mined out from under them or other modifications,
   -- because such a mining zone would automatically be merged with this one
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end
   
   local terrain = radiant.terrain.intersect_region(self._sv.region:get():translated(location))
   local bottom = Region3()
   for cube in terrain:each_cube() do
      bottom:add_cube(cube:get_face(-Point3.unit_y))
   end
   local unsupported = radiant.terrain.clip_region(bottom:translated(-Point3.unit_y)):translated(Point3.unit_y)
   -- ladder regions can be mined directly, so remove those from the unsupported region
   local ladders_region = self:get_ladders_region()
   if ladders_region then
      unsupported:subtract_region(ladders_region:translated(location))
   end

   -- now extend the unsupported region down by the max reach; if there's terrain anywhere within there, it's not really unsupported
   local reach_region = unsupported:translated(-Point3.unit_y):extruded('y', self._max_reach_up - 1, 0)
   local clipped = radiant.terrain.intersect_region(reach_region)
   unsupported:subtract_region(clipped:extruded('y', 0, self._max_reach_up))

   unsupported:translate(-location)
   self._sv._unsupported_region = unsupported
   self._sv._unsupported_buckets = nil
end

function AceMiningZoneComponent:get_unsupported()
   if not self._sv._unsupported_region then
      self:_update_unsupported()
   end
   return self._sv._unsupported_region
end

function AceMiningZoneComponent:get_next_unsupported_bucket(force_recalculate)
   local buckets = self:get_unsupported_buckets(force_recalculate)
   if buckets then
      local unsupported_region = self:get_unsupported()
      local bucket = buckets[#buckets]
      while bucket do
         -- over time, these get mined out, so intersect with our updated region
         -- no need to update all of these every time something gets mined
         bucket.region = bucket.region:intersect_region(unsupported_region)

         if bucket.region:empty() then
            log:debug('%s removing empty unsupported bucket %s for distance %s', self._entity, #buckets, bucket.distance)
            table.remove(buckets, #buckets)
            bucket = buckets[#buckets]
         else
            break
         end
      end

      if bucket then
         return bucket.region, bucket.distance
      end
   end

   return nil, nil
end

function AceMiningZoneComponent:get_unsupported_buckets(force_recalculate)
   if (force_recalculate or not self._sv._unsupported_buckets) and self._sv._unsupported_region and not self._sv._unsupported_region:empty() then
      local location = radiant.entities.get_world_grid_location(self._entity)
      local unsupported = self._sv._unsupported_region

      -- put all the unsupported blocks into buckets based on their distance from any of the foci: ladders (or if no ladders, closest-to-town/arbitrary edge point)
      -- since we're dealing with only the bottom-most unsupported blocks, treat it as a 2-dimensional problem and just use ladder regions
      local focus_region
      local ladders_region = self:get_ladders_region()

      if ladders_region and not ladders_region:empty() then
         ladders_region:optimize('bucketing unsupported blocks')
         focus_region = ladders_region
      else
         -- from closest-to-town point, try to find an adjacent supported block to use as focus
         local town = stonehearth.town:get_town(self._entity:get_player_id())
         local town_entity = town and (town:get_hearth() or town:get_banner())
         local town_entity_location = town_entity and town_entity:is_valid() and radiant.entities.get_world_grid_location(town_entity)
         local closest

         if town_entity_location then
            closest = unsupported:get_closest_point(town_entity_location - location)
         else
            -- no town to use so pick an arbitrary (corner) point on the edge
            local bounds = unsupported:get_bounds()
            closest = unsupported:get_closest_point(bounds.min)
         end

         focus_region = Region3()
         focus_region:add_point(closest)
      end

      local by_distance = {}
      local min_distance, max_distance
      for point in unsupported:each_point() do
         local distance
         for cube in focus_region:each_cube() do
            -- we need to be careful that we don't mine out two edges, leaving ourselves stuck on a corner
            -- so we can't do a radial distance, we have to do x + z (y in 2d classes)
            -- we end up with a lot of buckets this way, which means hearthlings will be running around a lot
            -- one way to improve could be grouping blocks that don't neighbor one another
            local cube_range = cube:get_closest_point(point) - point
            local cube_dist = math.abs(cube_range.x) + math.abs(cube_range.y) + math.abs(cube_range.z)
            if not distance or cube_dist < distance then
               distance = cube_dist
            end
         end
         
         if not min_distance or min_distance > distance then
            min_distance = distance
         end
         if not max_distance or max_distance < distance then
            max_distance = distance
         end

         local bucket = by_distance[distance]
         if not bucket then
            bucket = Region3()
            by_distance[distance] = bucket
         end
         bucket:add_point(point)
      end
      
      local buckets = {}
      -- set this up from closest to furthest so it's easy to remove buckets from the end of the table
      for d = min_distance, max_distance do
         local bucket = by_distance[d]
         if bucket then
            bucket:optimize('distance bucket')
            table.insert(buckets,
               {
                  distance = d,
                  region = bucket,
               })
         end
      end
      
      self._sv._unsupported_buckets = buckets
   end

   return self._sv._unsupported_buckets
end

function AceMiningZoneComponent:set_enabled(enabled)
   if self._sv.enabled == enabled then
      return
   end

   self._sv.enabled = enabled
   self.__saved_variables:mark_changed()

   -- ACE: check if there's a path to the town banner
   if enabled then
      self:_add_ladder_if_needed()
   end

   -- let the pathfinders know that the suitability of the mining zone has
   -- changed
   stonehearth.ai:reconsider_entity(self._entity, 'mining zone enable changed')

   -- let anyone who's interested know that our enable bit has changed (e.g. the mining action)
   radiant.events.trigger_async(self._entity, 'stonehearth:mining:enable_changed')

   self:update_requested_task()
end

function AceMiningZoneComponent:_add_ladder_if_needed()
   -- first check if there are any unfinished ladders; if so, let them get built before adding more
   if self._sv._ladder_handles then
      for _, handle in ipairs(self._sv._ladder_handles) do
         local builder = handle:get_builder()
         if builder and not builder:is_ladder_finished('build') then
            return
         end
      end
   end

   -- if there's space underneath the mining zone, add a ladder under the closest spot
   log:debug('%s enabling and checking if a ladder needs to be built...', self._entity)
   local town = stonehearth.town:get_town(self._entity:get_player_id())
   if town then
      local town_entity = town:get_hearth()
      local location = town_entity and town_entity:is_valid() and radiant.entities.get_world_grid_location(town_entity)
      if not location then
         town_entity = town:get_banner()
         location = town_entity and town_entity:is_valid() and radiant.entities.get_world_grid_location(town_entity)
         if not location then
            -- don't have a banner or hearth in the world? then don't bother
            return
         end
      end

      if not _radiant.sim.topology.are_connected(self._entity, town_entity) then
         local direct_path_finder = _radiant.sim.create_direct_path_finder(town_entity)
                                 :set_start_location(location)
                                 :set_destination_entity(self._entity)
                                 :set_allow_incomplete_path(true)
                                 :set_reversible_path(false)

         local path = direct_path_finder:get_path()
         -- if we found an incomplete path
         if path then
            local zone_location = radiant.entities.get_world_grid_location(self._entity)
            local destination = self._destination_component:get_region():get():translated(zone_location)
            local finish = path:get_finish_point()
            local closest = destination:get_closest_point(finish)

            -- the destination region might not reach to the bottom level of the mining region if it's floating in the air
            -- in that case, check the bottom of the actual mining region at this point
            local zone_region = self._sv.region:get():translated(zone_location)
            local bounds = zone_region:get_bounds()
            local bottom_point = zone_region:intersect_cube(Cube3(Point3(closest.x, bounds.min.y, closest.z), Point3(closest.x + 1, bounds.max.y, closest.z + 1))):get_bounds().min
            if bottom_point.y < closest.y then
               log:debug('%s destination region missing lower region point; using %s for closest', self._entity, bottom_point)
               closest = bottom_point
            end

            -- we expect the finish point to be at a lower y than the closest point
            -- and for there to be emptiness underneath the closest point
            log:debug('%s checking if %s is lower than %s, and there\'s emptiness under the latter...', self._entity, finish, closest)
            if finish.y < closest.y and not radiant.terrain.is_blocked(closest - Point3.unit_y) then
               finish.y = closest.y
               local facing = finish - closest
               facing:normalize()
               facing = facing:to_closest_int()
               -- if it's diagonal, we end up with a bad normal; need to 0 out the x or z, so pick one
               if facing.x ~= 0 and facing.z ~= 0 then
                  facing.x = 0
               elseif facing.x == 0 and facing.z == 0 then
                  facing.x = 1
               end
               self:create_ladder_handle(closest, facing)
            end
         else
            log:debug('%s no incomplete path found; cannot build helping ladder', self._entity)
         end
      else
         log:debug('%s complete path found; no ladder needed', self._entity)
      end
   end
end

-- point is in world space
-- need to override to handle loot quantity/quality properly when doubling loot from strength town bonus
function AceMiningZoneComponent:mine_point(point)
   local loot = {}

   -- When mining a point, need to inspect the specialized regions to see if the point is a part of them.
   -- Need to pull loot from the specific landmark_blocks table which was specified for this specialized region.
   local region = Region3(Cube3(point))
   local region_intersections = radiant.terrain.find_landmark_intersections(region)
   if #region_intersections > 0 then
      local region_index = region_intersections[1]
      local intersection = radiant.terrain.remove_region_from_landmark(region, region_index)
      loot = landmark_lib.get_loot_from_region(intersection, radiant.terrain._landmarks[region_index][2])
      log:debug('mined landmark point: %s', radiant.util.table_tostring(loot))
   else
      local block_kind = radiant.terrain.get_block_kind_at(point)
      loot = stonehearth.mining:roll_loot(block_kind)
      log:debug('mined point: %s', radiant.util.table_tostring(loot))
   end

   -- TODO: detect materials of loot items and only apply town bonuses if they apply
   -- If we have the strength town bonus, there's a chance we spawn more loot.
   local town = stonehearth.town:get_town(self._entity:get_player_id())
   if town then
      local strength_bonus = town:get_town_bonus('stonehearth:town_bonus:strength')
      if strength_bonus and strength_bonus:should_double_roll_mining_loot() then
         for uri, detail in pairs(loot) do
            for quality, quantity in pairs(detail) do
               detail[quality] = (detail[quality] or 0) + quantity
            end
         end
      end
   end

   stonehearth.mining:mine_point(point)

   local location = radiant.entities.get_world_grid_location(self._entity)
   local zone_region = self._sv.region:get()
   local unsupported_region = self:get_unsupported()
   unsupported_region:subtract_point(point - location)
   -- if we mined beneath a point, add that point to unsupported, provided it's not in a ladder region
   local above = point + Point3.unit_y - location
   if zone_region:contains(above) and radiant.terrain.contains(above + location) then
      -- check that there's no terrain within max reach below the above point
      if radiant.terrain.intersect_cube(Cube3(point):extruded('y', self._max_reach_up - 1, 0)):empty() then
         local ladders_region = self:get_ladders_region()
         if not ladders_region or not ladders_region:contains(above) then
            unsupported_region:add_point(above)
         end
      end
   end
   self:_update_destination()

   if self._destination_component:get_region():get():empty() then
      local unmined_region = self:_get_working_region(zone_region, location)
      if unmined_region:empty() then
         -- radiant.events.trigger_async(self, 'stonehearth:mining_zone:mining_complete')
         radiant.entities.destroy_entity(self._entity)
      end
   end

   return loot
end

function AceMiningZoneComponent:should_have_ladders()
   return self._sv._should_have_ladders
end

function AceMiningZoneComponent:has_ladders()
   return self._sv._ladder_handles and #self._sv._ladder_handles > 0
end

function AceMiningZoneComponent:get_ladders_region(zone_region)
   if zone_region and self._sv._ladders_region then
      -- limit ladder search to this zone
      return self._sv._ladders_region:intersect_region(zone_region)
   end

   return self._sv._ladders_region
end

function AceMiningZoneComponent:get_highest_y_at(block)
   local location = radiant.entities.get_world_grid_location(self._entity)
   if location then
      local zone_region = self._sv.region:get()
      local bounds = zone_region:get_bounds()
      local col = Cube3(block - location)
      col.min.y = bounds.min.y
      col.max.y = bounds.max.y

      local intersection = zone_region:intersect_region(Region3(col))
      if not intersection:empty() then
         return intersection:get_bounds().max.y + location.y
      end
   end
end

function AceMiningZoneComponent:should_build_ladder_at(block)
   -- check if there's a ladder in this cube already
   local location = radiant.entities.get_world_grid_location(self._entity)
   if location then
      local zone_point = block - location
      local zone_region = self._sv.region:get()
      for cube in zone_region:each_cube() do
         if cube:contains(zone_point) then
            local region = Region3(cube)
            local ladders_region = self:get_ladders_region(region)
            if not ladders_region or ladders_region:empty() then
               -- we don't have a ladder here; check if the height warrants having one
               region = radiant.terrain.intersect_region(region:translated(location))
               if not region:empty() then
                  local bounds = region:get_bounds()
                  if bounds.max.y - bounds.min.y > self._max_reach_up then
                     return true
                  end
               end
            end

            break
         end
      end
   end

   return false
end

function AceMiningZoneComponent:create_ladder_handle(block, normal, force_location)
   log:debug('%s create_ladder_handle(%s, %s, %s)', self._entity, block, normal, tostring(force_location))
   local point
   if force_location then
      point = block
   else
      -- try to create it at the bottom of the mining region in this spot
      local location = radiant.entities.get_world_grid_location(self._entity)
      local zone_region = self._sv.region:get():translated(location)
      local bounds = zone_region:get_bounds()
      local col = Cube3(block)
      col.min.y = bounds.min.y
      col.max.y = bounds.max.y

      local intersection = zone_region:intersect_region(Region3(col))
      if not intersection:empty() then
         local intersection_bounds = intersection:get_bounds()
         if intersection_bounds.min.y < block.y then
            point = intersection_bounds.min
         else
            point = block
         end

         local below = point - Point3.unit_y
         if not radiant.terrain.is_blocked(below) then
            point = radiant.terrain.get_standable_point(below)
            if point.y > below.y then
               log:debug('trying to create ladder through terrain above')
               return nil
            end
         end

         -- check if it even makes sense to build a ladder here (i.e., top of the zone here is higher from point than reach)
         if intersection_bounds.max.y - point.y <= self._max_reach_up then
            log:debug('%s point %s is <= %s distance from top in this col %s', self._entity, point, self._max_reach_up, intersection_bounds.max.y)
            return nil
         end
      end
   end

   if point then
      log:debug('%s creating ladder handle at %s (normal %s)', self._entity, point, normal)
      local handle = stonehearth.build:request_ladder_to(self._entity, point, normal, {force_build = true})
      self:add_ladder_handle(handle)
      return true
   end
end

function AceMiningZoneComponent:add_ladder_handle(handle, updating)
   if not self._sv._ladder_handles then
      self._sv._ladder_handles = {}
   end

   if not self._sv._ladders_region then
      self._sv._ladders_region = Region3()
   end

   local builder = handle:get_builder()
   if builder then
      local ladder = builder:get_ladder()
      if ladder and ladder:is_valid() then
         local location = radiant.entities.get_world_grid_location(ladder)
         if location then
            table.insert(self._sv._ladder_handles, handle)
            
            if not updating then
               local mine_location = radiant.entities.get_world_grid_location(self._entity)
               self:_update_ladder(handle, mine_location)
               self:_update_unsupported()
               self:_update_destination()
            end
         end
      end
   else
      log:debug('%s no builder for handle!', self._entity)
   end
end

function AceMiningZoneComponent:get_closest_ladder_handle(from)
   if not self._sv._ladder_handles then
      return nil
   end

   local best, best_distance
   for _, handle in ipairs(self._sv._ladder_handles) do
      local builder = handle:get_builder()
      if builder and not builder:is_ladder_finished('build') then
         local ladder = builder:get_ladder()
         if ladder and ladder:is_valid() then
            local location = radiant.entities.get_world_grid_location(ladder)
            if location then
               local distance = from:distance_to(location)
               if not best_distance or best_distance > distance then
                  best = handle
                  best_distance = distance
               end
            end
         end
      end
   end

   return best, best_distance
end

function AceMiningZoneComponent:_update_ladder_regions()
   if self._sv._ladder_handles then
      local mine_location = radiant.entities.get_world_grid_location(self._entity)
      for _, handle in ipairs(self._sv._ladder_handles) do
         self:_update_ladder(handle, mine_location)
      end
   end
end

function AceMiningZoneComponent:_update_ladder(handle, mine_location)
   local builder = handle:get_builder()
   if builder then
      local ladder = builder:get_ladder()
      if ladder and ladder:is_valid() then
         local location = radiant.entities.get_world_grid_location(ladder)
         if location then
            -- if it's higher than the ladder's top point, request the ladder get extended
            local req_point = self:get_ladder_request_point(location, mine_location)
            local ladder_component = ladder:get_component('stonehearth:ladder')

            if req_point and req_point.y > ladder_component:get_top().y then
               req_point = req_point - Point3.unit_y
               self:add_ladder_handle(builder:add_point(req_point, {user_removable = false}), true)
               --self._sv._adjacent_needs_ladder_update = true
               local ladder_cube = Cube3(location, req_point + Point3(1, 0, 1))
               log:debug('%s updating ladder region to %s', ladder, ladder_cube)
               self._sv._ladders_region:add_cube(ladder_cube:translated(-mine_location))
            end
         end
      end
   end
end

function AceMiningZoneComponent:get_ladder_request_point(location, mine_location)
   -- get the top point of the mining zone at this location
   local zone_region = self._sv.region:get():translated(mine_location)
   local bounds = zone_region:get_bounds()
   local col = Cube3(Point3(location.x, bounds.min.y, location.z), Point3(location.x + 1, bounds.max.y - 1, location.z + 1))
   local intersection = zone_region:intersect_cube(col)
   
   if not intersection:empty() then
      return Point3(location.x, intersection:get_bounds().max.y, location.z)
   end
end

-- ACE: creating a way to handle/manage mining from underneath by prioritizing mining upwards as far as possible and building a ladder along the way
-- if the height of the mining region is <= 3 and there are no ladders, it can't be mined from the top down, so just use normal logic
-- if the highest elevation in the region is the current standing level, mine from the highest elevation, furthest point
-- (if there is no ladder, then there is no "furthest point" and mining can be continued anywhere)
-- if there's already a ladder built to max point height, mine anything at that height or up to 2 below it
-- if there's already a ladder (handle), prioritize mining all the way to max point height
-- if there's no ladder handle and point height > 4, add one and prioritize mining in that column
-- otherwise simply prioritize mining in that column
-- to do this, manipulate the usage of the _get_working_region function:
--    while no ladders, allow mining anywhere
--    once ladder(s) added, only allow mining in top 4 and column(s) of ladder(s)

function AceMiningZoneComponent:_add_destination_blocks(destination_region, zone_region, zone_location)
   -- break the zone into convex regions (cubes) and run the destination block algorithm
   -- assumes the zone_region has been optimized already
   local exposed_region = Region3()
   for zone_cube in zone_region:each_cube() do
      local blocks = self:_get_destination_blocks_for_cube(zone_cube, zone_location, exposed_region)
      destination_region:add_region(blocks)
   end

   if destination_region:empty() then
      -- fallback condition: add unsupported blocks of the proper bucket
      self:_add_unsupported_blocks(destination_region, self:get_unsupported())

      -- if still empty, add all exposed blocks
      if destination_region:empty() and not exposed_region:empty() then
         log:debug('adding all exposed blocks to destination')
         destination_region:add_region(exposed_region)
      end

      if destination_region:empty() then
         log:debug('adding all blocks to destination')
         local working_region = self:_get_working_region(zone_region, zone_location)
         working_region:translate(-zone_location)
         destination_region:add_region(working_region)
      end
   end

   -- make sure all reserved blocks are part of the destination region
   local reserved_region = self._destination_component:get_reserved():get()
   destination_region:add_region(reserved_region)
end

-- this algorithm assumes a convex region, so we break the zone into cubes before running it
-- working_region is in world coordinates
-- destination_region and zone_cube are in local coordinates
function AceMiningZoneComponent:_get_destination_blocks_for_cube(zone_cube, zone_location, exposed_region)
   local up = Point3.unit_y
   local down = -Point3.unit_y
   local one = Point3.one
   local cube_region = Region3(zone_cube)
   local working_region = self:_get_working_region(cube_region, zone_location)
   local working_bounds = working_region:get_bounds()
   local unsupported_region = Region3()   -- ACE: currently ignoring this, we track unsupported in a different way
   local destination_region = Region3()

   -- for bottom facing, we do a separate restriction for which blocks are allowed
   local ladders_region = (self:get_ladders_region(cube_region) or Region3()):translated(zone_location)
   --log:debug('%s getting destination blocks for %s with ladders region %s', self._entity, zone_cube, ladders_region:get_bounds())

   local check_region
   if not ladders_region:empty() then
      -- add only the bottom facing blocks in the ladders region
      check_region = working_region:intersect_region(ladders_region)
   elseif self:should_build_ladder_at(working_bounds.min) then
      -- should we actually queue up ladder building here?
   else
      -- otherwise, add bottom facing blocks in whole region
      check_region = working_region
   end
   if check_region and not check_region:empty() then
      local check_bounds = check_region:get_bounds()
      self:_add_bottom_facing_blocks(destination_region, zone_location, check_region, check_bounds, unsupported_region)
   end

   -- for top and side-facing, we do the same restriction, so just do it now
   if not ladders_region:empty() then
      -- clip the region to the top reachable height and add in the ladder regions
      local clip_region = Region3(Cube3(Point3(working_bounds.min.x, working_bounds.max.y - self._max_reach_up, working_bounds.min.z), working_bounds.max))

      -- add the ladders
      clip_region:add_region(ladders_region)

      working_region = working_region:intersect_region(clip_region)
      working_bounds = working_region:get_bounds()
      --log:debug('limiting top/side checks to %s blocks in %s', working_region:get_area(), working_bounds)
   end
   self:_add_top_facing_blocks(destination_region, zone_location, working_region, working_bounds, unsupported_region)
   self:_add_side_facing_blocks(destination_region, zone_location, working_region, working_bounds, unsupported_region)
   
   if destination_region:empty() then
      -- fallback condition
      self:_add_all_exposed_blocks(exposed_region, zone_location, working_region)
   end

   return destination_region
end

function AceMiningZoneComponent:_add_top_facing_blocks(destination_region, zone_location, working_region, working_bounds, unsupported_region)
   local up = Point3.unit_y
   local down = -up
   local top_blocks = Region3()
   local other_blocks = Region3()
   local destination_blocks
   local working_bounds_max_y = working_bounds.max.y

   for cube in working_region:each_cube() do
      if cube.max.y >= working_bounds_max_y - MAX_DESTINATION_DELTA_Y then
         local top_face = cube:get_face(up)

         if top_face.max.y == working_bounds_max_y then
            top_blocks:add_unique_cube(top_face)
         else
            other_blocks:add_unique_cube(top_face)
         end
      end
   end

   -- Top blocks
   -- This skips the check that a block must be level with its neighbors before being mined,
   -- because all the blocks in this set are already on the top of the mining region.
   -- Roads and floors will both take this optimization.
   destination_blocks = top_blocks
   destination_blocks:translate(up)
   destination_blocks = radiant.terrain.clip_region(destination_blocks)
   destination_blocks:translate(down)

   local unsupported_blocks = self:_remove_unsupported_blocks(destination_blocks, zone_location)
   --log:debug('...adding %s top-facing blocks', destination_blocks:get_area())
   destination_blocks:translate(-zone_location)
   destination_region:add_region(destination_blocks)
   unsupported_region:add_region(unsupported_blocks)

   -- Other blocks
   -- The custom clip region makes sure that we can't dig down on a block until all its neighbors are level
   -- with the block. Make sure that terrain_region is clipped by the working bounds, as we don't want a
   -- terrain block outside any of the mining regions to prevent a block from being mined because it wasn't
   -- level with the terrain.
   if not other_blocks:empty() then
      local terrain_region = radiant.terrain.intersect_cube(working_bounds)
      terrain_region:set_tag(0)
      local custom_clip_region = terrain_region:inflated(Point3(1, 0, 1))

      destination_blocks = other_blocks
      destination_blocks:translate(up)
      destination_blocks:subtract_region(custom_clip_region)
      destination_blocks:translate(down)

      local unsupported_blocks = self:_remove_unsupported_blocks(destination_blocks, zone_location)
      --log:debug('...adding %s top-facing "other" blocks', destination_blocks:get_area())
      destination_blocks:translate(-zone_location)
      destination_region:add_region(destination_blocks)
      unsupported_region:add_region(unsupported_blocks)
   end
end

-- ACE: limit mining side-facing blocks in non-ladder columns below top reachable height
function AceMiningZoneComponent:_add_side_facing_blocks(destination_region, zone_location, working_region, working_bounds, unsupported_region)
   local up = Point3.unit_y
   local down = -up
   local destination_blocks = Region3()

   local get_exposed_blocks = function(slice, direction, working_region)
      local blocks = working_region:intersect_cube(slice)
      local full_slice = blocks:get_area() == slice:get_area()
      blocks:translate(direction)
      blocks = radiant.terrain.clip_region(blocks)
      blocks:translate(-direction)
      return blocks, full_slice
   end

   for _, direction in ipairs(csg_lib.XZ_DIRECTIONS) do
      local slice = working_bounds:get_face(direction)

      while true do
         local exposed_blocks, full_slice = get_exposed_blocks(slice, direction, working_region)
         if not exposed_blocks:empty() then
            destination_blocks:add_region(exposed_blocks)
            break
         end

         -- If the slice was fully occupied, don't bother to continue searching
         -- if full_slice then
         --    break
         -- end

         -- Look for exposed blocks on the next slice in
         slice:translate(-direction)

         -- Stop if the slice is out of bounds
         if not slice:intersects(working_bounds) then
            break
         end
      end
   end

   --log:debug('...removing unsupported blocks from %s side-facing blocks', destination_blocks:get_area())
   local unsupported_blocks = self:_remove_unsupported_blocks(destination_blocks, zone_location)
   --log:debug('...adding %s side-facing blocks', destination_blocks:get_area())
   destination_blocks:translate(-zone_location)
   destination_region:add_region(destination_blocks)
   unsupported_region:add_region(unsupported_blocks)
end

-- add bottom-facing blocks in short, ladderless regions, or in ladder columns
function AceMiningZoneComponent:_add_bottom_facing_blocks(destination_region, zone_location, working_region, working_bounds, unsupported_region)
   local direction = -Point3.unit_y
   local get_bottom_facing = function(slice, working_region)
      local blocks = working_region:intersect_cube(slice)
      local full_slice = blocks:get_area() == slice:get_area()
      blocks:translate(direction)
      blocks = radiant.terrain.clip_region(blocks)
      blocks:translate(-direction)
      return blocks, full_slice
   end

   local destination_blocks = Region3()
   for cube in working_region:each_cube() do
      local slice = cube:get_face(direction)

      while true do
         local bottom_facing, full_slice = get_bottom_facing(slice, working_region)
         if not bottom_facing:empty() then
            destination_blocks:add_region(bottom_facing)
            break
         end

         -- If the slice was fully occupied, don't bother to continue searching
         -- if full_slice then
         --    break
         -- end

         -- Look for exposed blocks on the next slice in
         slice:translate(-direction)

         -- Stop if the slice is out of bounds
         if not slice:intersects(working_bounds) then
            break
         end
      end
   end
   
   local unsupported_blocks = self:_remove_unsupported_blocks(destination_blocks, zone_location)
   --log:debug('...adding %s bottom-facing blocks', destination_blocks:get_area())
   destination_blocks:translate(-zone_location)
   destination_region:add_region(destination_blocks)
   unsupported_region:add_region(unsupported_blocks)
end

-- removes unsupported blocks from destimation blocks and returns the unsupported region
-- function MiningZoneComponent:_remove_unsupported_blocks(destination_blocks, check_top)
--    if check_top == nil then
--       check_top = true
--    end

--    local up = Point3.unit_y
--    local down = -up
--    local unsupported_blocks

--    if check_top then
--       -- project up to see if the top face is exposed
--       unsupported_blocks = radiant.terrain.clip_region(destination_blocks:translated(up))
--       unsupported_blocks:translate(down)
--    else
--       -- skipping a copy! DO NOT MODIFY unsupported_blocks!!!
--       unsupported_blocks = destination_blocks
--    end

--    -- project down to see if the bottom face is exposed
--    unsupported_blocks = radiant.terrain.clip_region(unsupported_blocks:translated(down))
--    unsupported_blocks:translate(up)

--    destination_blocks:subtract_region(unsupported_blocks)

--    return unsupported_blocks
-- end
function AceMiningZoneComponent:_remove_unsupported_blocks(destination_blocks, location)
   local unsupported_region = self:get_unsupported():translated(location)
   destination_blocks:subtract_region(unsupported_region)
   return Region3()  -- doesn't matter, we're not using them here
end

-- ACE: not actually changing anything, just the variable name destination_region to exposed_region
-- function AceMiningZoneComponent:_add_all_exposed_blocks(exposed_region, zone_location, working_region)
--    for cube in working_region:each_cube() do
--       for _, direction in ipairs(csg_lib.XYZ_DIRECTIONS) do
--          local face_region = Region3(cube:get_face(direction))
--          face_region:translate(direction)
--          radiant.terrain.clip_region(face_region)
--          face_region:translate(-direction - zone_location)
--          exposed_region:add_region(face_region)
--       end
--    end
-- end

function AceMiningZoneComponent:_add_unsupported_blocks(destination_region, unsupported_region)
   if not unsupported_region:empty() then
      local unsupported_bucket_region, distance = self:get_next_unsupported_bucket(true)
      if unsupported_bucket_region then
         log:debug('adding first bucket of unsupported blocks to destination')
         destination_region:add_region(unsupported_bucket_region)
      end
   end
end

-- -- get the unreserved terrain region that lies inside the zone_region
-- -- ACE: if ladders are specified, only look at the top 4 blocks of the working region, plus any columns of ladders
-- function AceMiningZoneComponent:_get_working_region(zone_region, zone_location)
--    local working_region = radiant.terrain.intersect_region(zone_region:translated(zone_location))
--    local reserved_region = self._destination_component:get_reserved():get():translated(zone_location)
--    working_region:subtract_region(reserved_region)
--    working_region:set_tag(0)

--    if not working_region:empty() then
--       local bounds = working_region:get_bounds()
--       -- don't need to bother clipping if there isn't enough to clip
--       if bounds.max.y - bounds.min.y > self._max_reach_up then
--          local ladders_region = self:get_ladders_region(zone_region)
--          if ladders_region and not ladders_region:empty() then
--             -- clip to the max reach below the top of the highest terrain
--             local top = bounds.max.y
--             local clip_region = Region3(Cube3(Point3(bounds.min.x, top - self._max_reach_up, bounds.min.z), bounds.max))

--             -- add the ladders
--             for p in ladders_region:translated(Point2(zone_location.x, zone_location.z)):each_cube() do
--                local col = Cube3(Point3(p.min.x, bounds.min.y, p.min.y), Point3(p.max.x + 1, top, p.max.y + 1))
--                -- only allow mining blocks with the bottom or top exposed
--                local intersection = working_region:intersect_region(Region3(col))
--                for ip in intersection:each_point() do
--                   if radiant.terrain.is_terrain(ip + Point3.unit_y) and radiant.terrain.is_terrain(ip - Point3.unit_y) then
--                      intersection:remove_point(ip)
--                   end
--                end
--                clip_region:add_region(intersection)
--                -- local bottom = not intersection:empty() and math.max(bounds.min.y, intersection:get_bounds().min.y - self._max_reach_up + 1)
--                -- if bottom then
--                --    clip_region:add_cube(Cube3(Point3(p.min.x, bottom, p.min.y), Point3(p.max.x, top, p.max.y)))
--                -- end
--             end

--             working_region = working_region:intersect_region(clip_region)
--          end
--       end
--    end

--    -- if there's something to mine other than unsupported blocks, restrict the destination to those
--    -- otherwise, restrict it to the next bucket of unsupported blocks
--    -- local unsupported_region = self:get_unsupported():translated(zone_location)
--    -- if not unsupported_region:empty() then
--    --    working_region:subtract_region(unsupported_region)
--    --    if working_region:empty() then
--    --       local unsupported_bucket_region, distance = self:get_next_unsupported_bucket()
--    --       if unsupported_bucket_region then
--    --          working_region = unsupported_bucket_region:translated(zone_location)
--    --       end
--    --    end
--    -- end

--    working_region:optimize('mining:_get_working_region()')
--    return working_region
-- end

function AceMiningZoneComponent:_update_adjacent()
   if self._sv._adjacent_needs_ladder_update then
      self:_update_adjacent_full()
   else
      self:_update_adjacent_incremental()
   end
end

-- slow version with an inner loop that is O(#_destination_blocks) / O(surface_area) of the mining region
function MiningZoneComponent:_update_adjacent_full()
   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end

   local unreserved_region = self:_get_unreserved_region()
   unreserved_region:translate(location)
   local adjacent = self:_calculate_adjacent(unreserved_region)

   -- if self._sv._adjacent_needs_ladder_update then
   --    self._sv._adjacent_needs_ladder_update = nil
   --    -- redo adjacency from scratch instead of just the recent modification
   --    -- need to account for ladder columns and also the working region being limited to the top 4 rows
   --    -- extend destination adjacency down by 4 from bottom in each ladder area
   --    local bounds = self._sv.region:get():get_bounds():translated(location)
   --    for cube in self:get_ladders_region():translated(location):each_cube() do
   --       local intersection = unreserved_region:intersect_region(cube)
   --       local bottom = not intersection:empty() and math.max(bounds.min.y, intersection:get_bounds().min.y - self._max_reach_up + 1)
   --       if bottom then
   --          adjacent:add_cube(Cube3(Point3(p.min.x, bottom, p.min.y), Point3(p.max.x, top, p.max.y)))
   --       end
   --    end
   -- end

   adjacent:translate(-location)

   self._destination_component:get_adjacent():modify(function(cursor)
         cursor:clear()
         cursor:add_region(adjacent)
         cursor:optimize('mining:_update_adjacent_full()')
      end)
end

return AceMiningZoneComponent
