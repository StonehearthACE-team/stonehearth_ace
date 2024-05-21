local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()
local ChooseLocationOutsideTown = require 'stonehearth.services.server.game_master.controllers.util.choose_location_outside_town'
local constants = stonehearth.constants.game_master.location_searcher
local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3

local MAX_POINTS_TO_CHECK = constants.MAX_POINTS_TO_CHECK or 700
local MAX_POINTS_TO_TRY_REACHABLE = constants.MAX_POINTS_TO_TRY_REACHABLE or 200
local MAX_POINTS_TO_CHECK_PER_LOOP = constants.MAX_POINTS_TO_CHECK_PER_LOOP or 4

local AceChooseLocationOutsideTown = class()

--Choose a location outside town to create something
--@param min_range - minimum range from the edge of town
--@param max_range - maximum range from the edge of town
--@param callback - fn to call when we've got the region
--@param target_region - optional, area around the target location to ensure is clear, for placing items
--@param player_id - optional, only consider this player's territory instead of everyone's.
-- ACE PARAMS:
--@param ensure_reachable - ensure that all the points will be tested if reachable instead of just some of them
--@param terrain_allowance - expects a table of allowed terrain types like this { dirt = true, stone = true }
--@param underwater - allows an underwater point to be selected if true; if 'required' it will *only* allow an underwater point.
--@param underground - allows an underground/tunnel point to be selected if true; if 'required' it will *only* allow an underground point.
AceChooseLocationOutsideTown._ace_old_create = ChooseLocationOutsideTown.create
function AceChooseLocationOutsideTown:create(min_range, max_range, callback, target_region, player_id, ensure_reachable, terrain_allowance, underwater, underground)
   self:_ace_old_create(min_range, max_range, callback, target_region, player_id)

   self._sv.ensure_reachable = ensure_reachable
   self._sv.terrain_allowance = terrain_allowance
   self._sv.underwater = underwater
   self._sv.underground = underground
end

function AceChooseLocationOutsideTown:_try_location(location, camp_region)
   local test_region

   if camp_region then
      -- Check that there is no terrain above the surface of the region
      if radiant.terrain.intersects_region(camp_region) then
         self._log:debug('location %s intersects terrain. trying again.', location)
         return false
      end

      -- Check that the region is supported by terrain
      local intersection = radiant.terrain.intersect_region(camp_region:translated(-Point3.unit_y))
      if intersection:get_area() ~= camp_region:get_area() then
         self._log:debug('location %s not flat. trying again.', location)
         return false
      end

      test_region = camp_region
   else
      test_region = Region3()
      test_region:add_point(location)
   end

   -- ACE: Check if underwater and if allowed
   local entities = radiant.terrain.get_entities_in_region(test_region)
   for _, entity in pairs(entities) do
      local water_component = entity:get_component('stonehearth:water')
      if water_component then
         if not self._sv.underwater then
            return false
         end
      else
         if self._sv.underwater and self._sv.underwater == 'required' then
            return false
         end
      end
   end

   -- ACE: Avoid tunnels or not, depending on settings
   local test_point = Point3(location)
   test_point.y = self._max_y
   local surface_point = radiant.terrain.get_point_on_terrain(test_point)
   if location ~= surface_point then
      if not self._sv.underground then
         return false
      end
   else
      if self._sv.underground and self._sv.underground == 'required' then
         return false
      end
   end

   -- ACE: Check the terrain allowance
   if self._sv.terrain_allowance and next(self._sv.terrain_allowance) ~= nil then
      local terrain_location = location
      terrain_location.y = terrain_location.y - 1 
      local tag = radiant.terrain.get_block_tag_at(terrain_location)
      local kind = radiant.terrain.get_block_kind_from_tag(tag)
      local name = radiant.terrain.get_block_name_from_tag(tag)
      if not (self._sv.terrain_allowance[kind] or self._sv.terrain_allowance[name]) then
         return false
      end
   end

   -- give the callback a shot...
   self._log:debug('About to check if I have a callback!')
   if self._sv.callback then
      self._log:info('Choose location got a callback! Calling it!')
      if not self:_invoke_callback('check_location', location, camp_region) then
         return false
      end
   end

   --if everything is fine, succeed!
   self._log:debug('found location %s', location)
   self:_finalize_location(location, camp_region)

   return true
end

function AceChooseLocationOutsideTown:_try_finding_location()
   -- Calculate the region covering the area we want to generate in.
   local territory = self._sv.player_id and stonehearth.terrain:get_territory(self._sv.player_id) or stonehearth.terrain:get_total_territory()
   local territory_region = territory:get_region()
   local valid_points_region = territory_region:inflated(Point2(self._sv.max_range, self._sv.max_range)) - territory_region:inflated(Point2(self._sv.min_range, self._sv.min_range))

   -- Set up a timer to measure our perf.
   local perf_timer = radiant.create_perf_timer()
   perf_timer:start()
   local function stop_timer(perf_timer, result, num_points)
      if perf_timer:is_running() then
         local ms = perf_timer:stop()
         if ms > 200 then
            local error_str = string.format('choose_location_outside_town took %dms to complete. Perimeter points searched: %d. Result: %s', ms, num_points, result)
            self._log:always(error_str)
         end
      end
   end

   if not valid_points_region:empty() then 
      -- Convert the region into a weighted set of cubes to pick from.
      local valid_cubes = WeightedSet(rng)
      for cube in valid_points_region:each_cube() do
         valid_cubes:add(cube, cube:get_area())
      end

      local reachability_check_location
      if self._sv.player_id then
         local town = stonehearth.town:get_town(self._sv.player_id)
         reachability_check_location = radiant.terrain.find_placement_point(town:get_landing_location(), 0, 10)
      else
         local hull = territory:get_convex_hull()
         if hull and #hull > 0 then
            reachability_check_location = radiant.terrain.get_point_on_terrain(Point3(hull[1].x, self._max_y, hull[1].y))
            reachability_check_location.y = reachability_check_location.y + 1  -- The point should be *on top* of the terrain.
         end
      end

      -- Keep choosing random points until we hit a valid one or reach our maximum.
      -- In theory, this is unreliable, but in practice, since we're typically dealing
      -- with 10k+ available points, it's quite robust. We could guarantee a full random
      -- iteration by using an LCG, but that's likely overkill in practice.
      local max_points = math.min(valid_points_region:get_area(), MAX_POINTS_TO_CHECK)
      local point_with_reachable_check_remaining = reachability_check_location and self._sv.ensure_reachable and MAX_POINTS_TO_CHECK or reachability_check_location and MAX_POINTS_TO_TRY_REACHABLE or 0
      while self._points_checked < max_points do
         self._points_checked = self._points_checked + 1

         local cube = valid_cubes:choose_random()
         local point = radiant.terrain.get_point_on_terrain(Point3(rng:get_int(cube.min.x, cube.max.x), self._max_y, rng:get_int(cube.min.y, cube.max.y)))

         local reachability_check_passed = true
         if point_with_reachable_check_remaining > 0 then
            reachability_check_passed = _radiant.sim.topology.are_strictly_connected(point, reachability_check_location, 0)
            point_with_reachable_check_remaining = point_with_reachable_check_remaining - 1
         end

         if reachability_check_passed then
            local camp_region = self:_get_camp_region(point)
            local found = self:_try_location(point, camp_region)
            if found or self._sv.destroyed then
               stop_timer(perf_timer, 'found a location', self._points_checked)
               self:destroy()
               return
            end

            if self._points_checked % MAX_POINTS_TO_CHECK_PER_LOOP == 0 then
               coroutine.yield()
               if self._sv.destroyed then
                  return
               end
            end
         end
      end
   end

   -- If the loop finished without returning, then we couldn't find a valid point.
   self._log:warning('all convex hull points searched. aborting camp placement.')
   stop_timer(perf_timer, 'aborting. all convex hull points searched.', self._points_checked)
   if self._sv.callback then
      self:_invoke_callback('abort')
   end
   self:destroy()
end

return AceChooseLocationOutsideTown
