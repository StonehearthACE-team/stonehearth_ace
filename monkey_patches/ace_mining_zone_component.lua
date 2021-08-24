local landmark_lib = require 'stonehearth.lib.landmark.landmark_lib'

local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3
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
            lh:get_builder():destroy_immediately()
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

   self:_update_destination()
   self:_update_designation()
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

   self:_update_destination()

   if self._destination_component:get_region():get():empty() then
      local location = radiant.entities.get_world_grid_location(self._entity)
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

function AceMiningZoneComponent:get_ladders_region()
   return self._sv._ladders_region
end

function AceMiningZoneComponent:create_ladder_handle(block, normal)
   -- create it at the bottom of the mining region in this spot
   local zone_region = self._sv.region:get()
   local bounds = zone_region:get_bounds()
   local col = Cube3(block)
   col.min.y = bounds.min.y
   col.max.y = bounds.max.y
   local intersection = zone_region:intersect_region(Region3(col))
   if not intersection:empty() then
      local point = intersection:get_bounds().min
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
