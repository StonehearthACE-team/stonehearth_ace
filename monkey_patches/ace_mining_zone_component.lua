local landmark_lib = require 'stonehearth.lib.landmark.landmark_lib'

local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Rect2 = _radiant.csg.Rect2
local Cube3 = _radiant.csg.Cube3
local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3
local build_util = require 'stonehearth.lib.build_util'
local log = radiant.log.create_logger('mining')

local MiningZoneComponent = require 'stonehearth.components.mining_zone.mining_zone_component'
local AceMiningZoneComponent = class()

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
            stonehearth.build:remove_ladder_command({player_id = self._entity:get_player_id()}, nil, builder:get_ladder())
         else
            lh:destroy()
         end
      end
      self._sv._ladder_handles = nil
   end
end

function AceMiningZoneComponent:_on_region_changed()
   -- cache the region bounds.  force optimize before caching to make
   -- sure we absolutely have the minimal region.  not having the smallest
   -- region possible will have cascading performance problems down the
   -- line.
   self._sv.region:modify(function(cursor)
      cursor:set_tag(0)
      cursor:force_optimize('mining zone region changed')
      log:debug('mining zone contains %d cubes', cursor:get_num_rects())
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
   local terrain = radiant.terrain.intersect_region(self._sv.region:get():translated(location))
   local bottom = Region3()
   for cube in terrain:each_cube() do
      bottom:add_cube(cube:get_face(-Point3.unit_y))
   end
   local unsupported = radiant.terrain.clip_region(bottom:translated(-Point3.unit_y)):translated(Point3.unit_y - location)
   -- ladder regions can be mined directly, so remove those from the unsupported region
   local ladders_region = self:get_ladders_region()
   if ladders_region then
      local bounds = unsupported:get_bounds()
      local ladders_r3 = Region3()
      for rect in ladders_region:each_cube() do
         ladders_r3:add_cube(Cube3(Point3(rect.min.x, bounds.min.y, rect.min.y), Point3(rect.max.x, bounds.max.y, rect.max.y)))
      end
      unsupported:subtract_region(ladders_r3)
   end

   self._sv._unsupported_region = unsupported
   self._sv._unsupported_buckets = nil
end

function AceMiningZoneComponent:get_unsupported()
   if not self._sv._unsupported_region then
      self:_update_unsupported()
   end
   return self._sv._unsupported_region
end

function AceMiningZoneComponent:get_next_unsupported_bucket()
   local buckets = self:get_unsupported_buckets()
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

function AceMiningZoneComponent:get_unsupported_buckets()
   if not self._sv._unsupported_buckets and self._sv._unsupported_region and not self._sv._unsupported_region:empty() then
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

         focus_region = Region2()
         focus_region:add_point(Point2(closest.x, closest.z))
      end

      local by_distance = {}
      local min_distance, max_distance
      for point in unsupported:each_point() do
         local pt2 = Point2(point.x, point.z)
         local distance
         for rect in focus_region:each_cube() do
            -- we need to be careful that we don't mine out two edges, leaving ourselves stuck on a corner
            -- so we can't do a radial distance, we have to do x + z (y in 2d classes)
            -- we end up with a lot of buckets this way, which means hearthlings will be running around a lot
            -- one way to improve could be grouping blocks that don't neighbor one another
            --local rect_dist = rect:distance_to(Point2(point.x, point.z)))
            local closest_focus = rect:get_closest_point(pt2)
            local rect_dist = math.abs(pt2.x - closest_focus.x) + math.abs(pt2.y - closest_focus.y)
            if not distance or rect_dist < distance then
               distance = rect_dist
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

   -- ACE: if no ladders, check if there's a path to the town banner
   -- if not, and there's space underneath the mining zone, add a ladder under the closest spot
   -- TODO: need to figure out what happens when one ladder isn't enough
   if enabled and not self:has_ladders() then
      log:debug('%s enabling and checking if a ladder needs to be built...', self._entity)
      local town = stonehearth.town:get_town(self._entity:get_player_id())
      if town then
         local town_entity = town:get_hearth() or town:get_banner()
         if town_entity and town_entity:is_valid() then
            local location = radiant.entities.get_world_grid_location(town_entity)
            -- try for a complete path first; if one exists, we don't need any ladders
            local direct_path_finder = _radiant.sim.create_direct_path_finder(town_entity)
                                       :set_start_location(location)
                                       :set_destination_entity(self._entity)
                                       :set_allow_incomplete_path(false)
                                       :set_reversible_path(false)

            local path = direct_path_finder:get_path()
            if not path then
               direct_path_finder = _radiant.sim.create_direct_path_finder(town_entity)
                                       :set_start_location(location)
                                       :set_destination_entity(self._entity)
                                       :set_allow_incomplete_path(true)
                                       :set_reversible_path(false)

               path = direct_path_finder:get_path()
               -- if we found an incomplete path
               if path then
                  local zone_location = radiant.entities.get_world_grid_location(self._entity)
                  local destination = self._destination_component:get_region():get():translated(zone_location)
                  local finish = path:get_finish_point()
                  local closest = destination:get_closest_point(finish)

                  -- we expect the finish point to be at a lower y than the closest point
                  -- and for there to be emptiness underneath the closest point
                  log:debug('%s checking if %s is lower than %s, and there\'s emptiness under the latter...', self._entity, finish, closest)
                  if finish.y < closest.y and not radiant.terrain.is_blocked(closest - Point3.unit_y) then
                     location.y = finish.y
                     local facing = location - finish
                     facing:normalize()
                     facing = facing:to_closest_int()
                     -- if it's diagonal, we end up with a bad normal; need to 0 out the x or z, so pick one
                     if facing.x ~= 0 and facing.z ~= 0 then
                        facing.x = 0
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
   end

   -- let the pathfinders know that the suitability of the mining zone has
   -- changed
   stonehearth.ai:reconsider_entity(self._entity, 'mining zone enable changed')

   -- let anyone who's interested know that our enable bit has changed (e.g. the mining action)
   radiant.events.trigger_async(self._entity, 'stonehearth:mining:enable_changed')

   self:update_requested_task()
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
   else
      local block_kind = radiant.terrain.get_block_kind_at(point)
      loot = stonehearth.mining:roll_loot(block_kind)
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
   local unsupported_region = self:get_unsupported()
   unsupported_region:subtract_point(point - location)
   self:_update_destination()

   if self._destination_component:get_region():get():empty() then
      local zone_region = self._sv.region:get()
      local unmined_region = self:_get_working_region(zone_region, location)
      if unmined_region:empty() then
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

function AceMiningZoneComponent:get_ladders_region()
   return self._sv._ladders_region
end

function AceMiningZoneComponent:create_ladder_handle(block, normal, force_location)
   log:debug('%s create_ladder_handle(%s, %s, %s)', self._entity, block, normal, tostring(force_location))
   local point
   if force_location then
      point = block
   else
      -- create it at the bottom of the mining region in this spot
      local location = radiant.entities.get_world_grid_location(self._entity)
      local zone_region = self._sv.region:get():translated(location)
      local bounds = zone_region:get_bounds()
      local col = Cube3(block)
      col.min.y = bounds.min.y
      col.max.y = bounds.max.y
      local intersection = zone_region:intersect_region(Region3(col))
      if not intersection:empty() then
         point = intersection:get_bounds().min
         local below = point - Point3.unit_y
         if not radiant.terrain.is_blocked(below) then
            point = radiant.terrain.get_standable_point(below)
         end
      end
   end

   if point then
      log:debug('%s creating ladder handle at %s (normal %s)', self._entity, point, normal)
      local handle = stonehearth.build:request_ladder_to(self._entity, point, normal)
      self:add_ladder_handle(handle)
   end
end

function AceMiningZoneComponent:add_ladder_handle(handle, updating)
   if not self._sv._ladder_handles then
      self._sv._ladder_handles = {}
   end

   if not self._sv._ladders_region then
      self._sv._ladders_region = Region2()
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
               location = location - mine_location
               self._sv._ladders_region:add_point(Point2(location.x, location.z))
               self:_update_unsupported()
               self:_update_destination()
            end
         end
      end
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
               self:add_ladder_handle(builder:add_point(req_point, {user_removable = false}), true)
               self._sv._adjacent_needs_ladder_update = true
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
   local intersection = zone_region:intersect_region(Region3(col))
   
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
   local working_region = self:_get_working_region(zone_region, zone_location)
   working_region:translate(-zone_location)
   destination_region:add_region(working_region)

   -- make sure all reserved blocks are part of the destination region
   local reserved_region = self._destination_component:get_reserved():get()
   destination_region:add_region(reserved_region)
end

-- get the unreserved terrain region that lies inside the zone_region
-- ACE: if ladders are specified, only look at the top 4 blocks of the working region, plus any columns of ladders
function AceMiningZoneComponent:_get_working_region(zone_region, zone_location)
   local working_region = radiant.terrain.intersect_region(zone_region:translated(zone_location))
   local reserved_region = self._destination_component:get_reserved():get():translated(zone_location)
   working_region:subtract_region(reserved_region)
   working_region:set_tag(0)

   if not working_region:empty() then
      local bounds = working_region:get_bounds()
      -- don't need to bother clipping if there isn't enough to clip
      if bounds.max.y - bounds.min.y > self._max_reach_up then
         local ladders_region = self:get_ladders_region()
         if ladders_region and not ladders_region:empty() then
            local top = bounds.max.y
            local clip_region = Region3(Cube3(Point3(bounds.min.x, top - self._max_reach_up, bounds.min.z), bounds.max))
            -- add the ladders
            for p in ladders_region:translated(Point2(zone_location.x, zone_location.z)):each_cube() do
               local col = Cube3(Point3(p.min.x, bounds.min.y, p.min.y), Point3(p.max.x + 1, top, p.max.y + 1))
               local intersection = working_region:intersect_region(Region3(col))
               local bottom = not intersection:empty() and math.max(bounds.min.y, intersection:get_bounds().min.y - self._max_reach_up + 1)
               if bottom then
                  clip_region:add_cube(Cube3(Point3(p.min.x, bottom, p.min.y), Point3(p.max.x, top, p.max.y)))
               end
            end

            working_region = working_region:intersect_region(clip_region)
         end
      end
   end

   -- if there's something to mine other than unsupported blocks, restrict the destination to those
   -- otherwise, restrict it to the next bucket of unsupported blocks
   local unsupported_region = self:get_unsupported():translated(zone_location)
   if not unsupported_region:empty() then
      working_region:subtract_region(unsupported_region)
      if working_region:empty() then
         local unsupported_bucket_region, distance = self:get_next_unsupported_bucket()
         if unsupported_bucket_region then
            working_region = unsupported_bucket_region:translated(zone_location)
         end
      end
   end

   working_region:optimize('mining:_get_working_region()')
   return working_region
end

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

   if self._sv._adjacent_needs_ladder_update then
      self._sv._adjacent_needs_ladder_update = nil
      -- redo adjacency from scratch instead of just the recent modification
      -- need to account for ladder columns and also the working region being limited to the top 4 rows
      -- extend destination adjacency down by 4 from bottom in each ladder area
      local bounds = self._sv.region:get():get_bounds():translated(location)
      local top = bounds.max.y
      for p in self:get_ladders_region():translated(Point2(location.x, location.z)):each_cube() do
         local col = Cube3(Point3(p.min.x, bounds.min.y, p.min.y), Point3(p.max.x + 1, top, p.max.y + 1))
         local intersection = unreserved_region:intersect_region(Region3(col))
         local bottom = not intersection:empty() and math.max(bounds.min.y, intersection:get_bounds().min.y - self._max_reach_up + 1)
         if bottom then
            adjacent:add_cube(Cube3(Point3(p.min.x, bottom, p.min.y), Point3(p.max.x, top, p.max.y)))
         end
      end
   end

   adjacent:translate(-location)

   self._destination_component:get_adjacent():modify(function(cursor)
         cursor:clear()
         cursor:add_region(adjacent)
         cursor:optimize('mining:_update_adjacent_full()')
      end)
end

return AceMiningZoneComponent
