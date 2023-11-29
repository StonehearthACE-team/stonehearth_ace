local log = radiant.log.create_logger('mutation_utils')

local Region3 = _radiant.csg.Region3
local Point3 = _radiant.csg.Point3

local FixtureData = require 'stonehearth.lib.building.fixture_data'
local RoofData = require 'stonehearth.lib.building.roof_data'
local RoomData = require 'stonehearth.lib.building.room_data'
local WallData = require 'stonehearth.lib.building.wall_data'
local PerimeterWallData = require 'stonehearth.lib.building.perimeter_wall_data'
local BlocksData = require 'stonehearth.lib.building.blocks_data'
local StairsData = require 'stonehearth.lib.building.stairs_data'

local Building = 'stonehearth:build2:building'

local Builder = radiant.class()

function Builder:__init(data)
   self._data = data
   self._masks = radiant.shallow_copy(data.masks)
   self._masked = radiant.shallow_copy(data.masked)
   self._supports = radiant.shallow_copy(data.supports)
   self._supported = radiant.shallow_copy(data.supported)
   self._adjacent = radiant.shallow_copy(data.adjacent)
end

function Builder:get_data()
   return self._data
end

function Builder:clear_masks()
   self._masks = {}
   self._masked = {}
end

function Builder:clear_supports(ignored_bids)
   for bid, _ in pairs(self._supported) do
      if not ignored_bids[bid] then
         self._supported[bid] = nil
      end
   end

   for bid, _ in pairs(self._supports) do
      if not ignored_bids[bid] then
         self._supports[bid] = nil
      end
   end

   for bid, _ in pairs(self._adjacent) do
      if not ignored_bids[bid] then
         self._adjacent[bid] = nil
      end
   end
end

function Builder:add_mask(bid)
   assert(not self._masked[bid], self._data:get_bid() .. ' is already masking ' .. bid)
   self._masks[bid] = true
end

function Builder:add_masked(bid)
   assert(not self._masks[bid], self._data:get_bid() .. ' is already masked by ' .. bid)
   self._masked[bid] = true
end

function Builder:remove_mask(bid)
   self._masks[bid] = nil
end

function Builder:remove_masked(bid)
   self._masked[bid] = nil
end

function Builder:masks(bid)
   return self._masked[bid]
end

function Builder:add_supported(bid)
   self._supported[bid] = true
   assert(not self._supports[bid], tostring(bid) .. ' supported by ' .. self._data:get_bid())
end

function Builder:remove_supported(bid)
   self._supported[bid] = nil
end

function Builder:supported(bid)
   return self._supported[bid] ~= nil
end

function Builder:add_support(bid)
   self._supports[bid] = true
   assert(not self._supported[bid], tostring(bid) .. ' supports ' .. self._data:get_bid())
end

function Builder:remove_support(bid)
   self._supports[bid] = nil
end

function Builder:add_adjacent(bid)
   self._adjacent[bid] = true
end

function Builder:remove_adjacent(bid)
   self._adjacent[bid] = nil
end

function Builder:supports(bid)
   return self._supports[bid] ~= nil
end

function Builder:build()
   local d = self._data:_new({
         masks = self._masks,
         masked = self._masked,
         supported = self._supported,
         supports = self._supports,
         adjacent = self._adjacent,
      })
   return d
end

local BuilderCache = radiant.class()

function BuilderCache:__init()
   self._touched = {}
end

function BuilderCache:get(bid)
   local result = self._touched[bid]
   if not result then
      result = Builder(stonehearth.building:get_data(bid))
      self._touched[bid] = result
   end
   return result
end

function BuilderCache:has(bid)
   return self._touched[bid] ~= nil
end

function BuilderCache:flush()
   for _, builder in pairs(self._touched) do
      stonehearth.building:mutate_data(builder:build())
   end
   self._touched = {}
end

local function _filter_removed(bids)
   local _, _, removed = stonehearth.building:get_all_mutation_data()
   return radiant.filter(bids, function(bid, _)
         return not removed[bid]
      end)
end

local function _get_bid(e)
   local bp = e:get('stonehearth:build2:blueprint')
   if bp then
      return bp:get_bid()
   end
   return nil
end

local function _filter_overlapping_fn(e, building_id, ignored_bids)
   local other_bid = _get_bid(e)
   if other_bid and not ignored_bids[other_bid] and stonehearth.building:has_data(other_bid) then
      local data = stonehearth.building:get_data(other_bid)
      return data:get_building_id() == building_id
   end
   return false
end

local function _get_overlapping_blueprints(building_id, shape_w, ignored_bids)
   if shape_w.get_bounds then
      return radiant.terrain.get_entities_in_region(shape_w, function(e)
            return _filter_overlapping_fn(e, building_id, ignored_bids)
         end)
   else
      return radiant.terrain.get_entities_in_cube(shape_w, function(e)
            return _filter_overlapping_fn(e, building_id, ignored_bids)
         end)
   end
end

local function _get_overlapping_data(building_id, shape_w, ignored_bids, include_fixtures)
   local bps = _get_overlapping_blueprints(building_id, shape_w, ignored_bids)

   local result = {}
   for _, bp in pairs(bps) do
      local data = stonehearth.building:get_data(bp:get('stonehearth:build2:blueprint'):get_bid())
      if include_fixtures or data:get_uri() ~= FixtureData.URI then
         if data:get_world_shape():intersects_region(shape_w) then
            result[data:get_bid()] = data
         end
      end
   end

   return result
end

local function _get_bids(datum)
   local result = {}

   for _, d in pairs(datum) do
      result[d:get_bid()] = true
   end

   return result
end

local function _get_datum(bids)
   local result = {}

   for bid, _ in pairs(bids) do
      result[bid] = stonehearth.building:get_data(bid)
   end

   return result
end

local function _get_all_exclusively_supported(bids)
   local function _get_supported_for(bid, results)
      local data = stonehearth.building:get_data(bid)
      for other_bid, _ in pairs(data:get_supports()) do
         if not results[other_bid] then
            results[other_bid] = true
            _get_supported_for(other_bid, results)
         end
      end
      for other_bid, _ in pairs(data:get_adjacent()) do
         if not results[other_bid] then
            local other_data = stonehearth.building:get_data(other_bid)
            -- Only consider adjacencies that are blocks AND those blocks are not supported by other
            -- structures OR the terrain.
            if other_data:get_uri() == BlocksData.URI and (radiant.empty(other_data:get_supported()) and
                  not radiant.terrain.region_intersects_terrain(other_data:get_world_shape():translated(Point3(0, -1, 0)))) then
               results[other_bid] = true
               _get_supported_for(other_bid, results)
            end
         end
      end
   end

   local results = {}

   for bid, _ in pairs(bids) do
      results[bid] = true
      _get_supported_for(bid, results)
   end
   return results
end

local function _get_all_supported(bids)
   local function _get_supported_for(bid, results)
      local data = stonehearth.building:get_data(bid)
      for other_bid, _ in pairs(data:get_supports()) do
         if not results[other_bid] then
            results[other_bid] = true
            _get_supported_for(other_bid, results)
         end
      end
      for other_bid, _ in pairs(data:get_adjacent()) do
         if not results[other_bid] and stonehearth.building:get_data(other_bid):get_uri() == BlocksData.URI then
            results[other_bid] = true
            _get_supported_for(other_bid, results)
         end
      end
   end

   local results = {}

   for bid, _ in pairs(bids) do
      results[bid] = true
      _get_supported_for(bid, results)
   end
   return results
end

local _sides = {Point3(-1, 0, 0), Point3(1, 0, 0), Point3(0, 0, -1), Point3(0, 0, 1)}
local function _recompute_supports(bids, builders)
   local _filter_valid = function(m)
      local r = {}
      for k, v in pairs(m) do
         if stonehearth.building:has_data(k) then
            local uri = stonehearth.building:get_data(k):get_uri()
            if uri ~= FixtureData.URI then
               r[k] = v
            end
         end
      end
      return r
   end

   if not radiant.is_server then
      return
   end

   bids = _filter_valid(bids)

   for bid, _ in pairs(bids) do
      local data = stonehearth.building:get_data(bid)
      local builder = builders:get(bid)
      local shape_w = data:get_world_shape()

      -- Store everyone overlapping us.
      local overlapping = _get_overlapping_data(data:get_building_id(), shape_w, bids)

      -- Get everyone below us, excluding ourselves.
      local supported = _get_overlapping_data(data:get_building_id(), shape_w:translated(Point3(0, -1, 0)), bids)
      for other_bid, other_data in pairs(supported) do
         if not overlapping[other_bid] and not builder:supports(other_bid)then
            local other_builder = builders:get(other_bid)
            builder:add_supported(other_bid)
            other_builder:add_support(bid)
         end
      end

      local supports = _get_overlapping_data(data:get_building_id(), shape_w:translated(Point3(0, 1, 0)), bids)
      for other_bid, other_data in pairs(supports) do
         if not overlapping[other_bid] and not builder:supported(other_bid) then
            local other_builder = builders:get(other_bid)
            builder:add_support(other_bid)
            other_builder:add_supported(bid)
         end
      end

      for _, side in ipairs(_sides) do
         local adjacents = _get_overlapping_data(data:get_building_id(), shape_w:translated(side), bids)
         for other_bid, other_data in pairs(adjacents) do
            if other_data:get_uri() == BlocksData.URI or data:get_uri() == BlocksData.URI or
               other_data:get_uri() == RoofData.URI or data:get_uri() == RoofData.URI then
               local other_builder = builders:get(other_bid)

               other_builder:add_adjacent(bid)
               builder:add_adjacent(other_bid)
            end
         end
      end
   end
end

local mutation_utils = {}

local function _embedded_valid(shape_w)
   -- ACE: who cares about terrain?! Let's just mine it all!

   -- -- Embedded in terrain.  Ensure that it's only one unit down.
   -- local bottom_shape_w = shape_w:peel(Point3(0, 1, 0))
   -- local top_shape_w = shape_w - bottom_shape_w

   -- if top_shape_w:empty() then
   --    local es = radiant.terrain.get_entities_in_region(bottom_shape_w:translated(Point3(0, 1, 0)))
   --    for _, e in pairs(es) do
   --       if e:get_id() == radiant._root_entity_id then
   --          return false
   --       end
   --    end
   -- else
   --    local es = radiant.terrain.get_entities_in_region(top_shape_w)
   --    for _, e in pairs(es) do
   --       if e:get_id() == radiant._root_entity_id then
   --          return false
   --       end
   --    end
   -- end

   return true
end

-- Trivial support iff: not intersecting another building, or another building's envelope; if not floating, then resting on the terrain.
local function _trivial_support(building_id, shape_w)
   local es = radiant.terrain.get_entities_in_region(shape_w)
   local embedded = false

   for _, e in pairs(es) do
      if radiant.entities.is_solid_entity(e) then
         if e:get_id() == radiant._root_entity_id then
            embedded = true
         else
            return false
         end
      end

      if e:get_uri() == 'stonehearth:build2:entities:envelope' then
         return false
      end

      local bc = e:get('stonehearth:build2:blueprint')

      if bc and bc:get_data():get_building_id() ~= building_id then
         return false
      end
   end

   if not embedded then
      local es = radiant.terrain.get_entities_in_region(shape_w:translated(Point3(0, -1, 0)))

      for _, e in pairs(es) do
         if radiant.entities.is_solid_entity(e) then
            return true
         end
      end
      return false
   end

   return true
end

local function _recompute_validity(building_id)
   local all_bids = stonehearth.building:get_building(building_id):get(Building):get_all_bids()

   all_bids = _filter_removed(all_bids)
   -- Find every root to the world we can.

   local valid_mutated = {}
   local strictly_invalid = {}
   local mutated, added, removed = stonehearth.building:get_all_mutation_data()

   -- Non-mutated structures that are marked as valid are good.
   for bid, _ in pairs(all_bids) do
      if not mutated[bid] and not added[bid] and not stonehearth.building:get_data(bid):is_invalid_placement() then
         valid_mutated[bid] = true
         all_bids[bid] = nil
      end
   end

   -- Mutated structures that are on the world are also valid.
   for bid, data in pairs(mutated) do
      local ws = data:get_world_shape()
      if _trivial_support(data:get_building_id(), ws) then
         if _embedded_valid(ws) then
            valid_mutated[bid] = true
            all_bids[bid] = nil
         else
            strictly_invalid[bid] = true
         end
      end
   end
   for bid, data in pairs(added) do
      local ws = data:get_world_shape()
      all_bids[bid] = true
      if _trivial_support(data:get_building_id(), ws) then
         if _embedded_valid(ws) then
            valid_mutated[bid] = true
            all_bids[bid] = nil
         else
            strictly_invalid[bid] = true
         end
      end
   end

   -- From those left, build up the graphs of everyone that successfuly touches the ground.
   -- (Anything left over must be invalid.)
   local function _path_to_valid(data, visited)
      for bid, _ in pairs(data:get_supports()) do
         if not visited[bid] then
            visited[bid] = true
            valid_mutated[bid] = true
            _path_to_valid(stonehearth.building:get_data(bid), visited)
         end
      end

      for bid, _ in pairs(data:get_adjacent()) do
         if not visited[bid] then
            visited[bid] = true
            valid_mutated[bid] = true
            _path_to_valid(stonehearth.building:get_data(bid), visited)
         end
      end
   end

   local roots = radiant.shallow_copy(valid_mutated)
   local visited = radiant.shallow_copy(valid_mutated)
   for bid, _ in pairs(roots) do
      _path_to_valid(stonehearth.building:get_data(bid), visited)
   end

   -- Should probably handle this in the traversal, for clarity, but this ought to
   -- be good enough: anything embedded is right out.
   for bid, _ in pairs(strictly_invalid) do
      valid_mutated[bid] = false
   end

   all_bids = stonehearth.building:get_building(building_id):get(Building):get_all_bids()
   for bid, _ in pairs(added) do
      all_bids[bid] = true
   end
   for bid, _ in pairs(all_bids) do
      local data = stonehearth.building:get_data(bid)
      local valid = not data:is_invalid_placement()
      local new_valid = valid_mutated[bid] or false
      if valid ~= new_valid then
         stonehearth.building:mutate_data(data:set_invalid(not new_valid))
      end
   end
end

function mutation_utils._overlapping_rooms(rooms)
   local all_data = {}
   for _, room in pairs(rooms) do
      table.insert(all_data, room)

      if stonehearth.building:has_data(room:get_bid()) then
         table.insert(all_data, stonehearth.building:get_blueprint(room:get_bid()):get_data())
      end
   end

   -- all_data should contain both present and future data; we want to find all
   -- current rooms that overlap.
   local overlap = {}
   for _, data in ipairs(all_data) do
      local world_floor = data:get_world_shape()
      local all_floors = radiant.terrain.get_entities_in_region(world_floor, function(e)
            return e:get_uri() == RoomData.URI
         end)

      for _, f in pairs(all_floors) do
         local d = f:get('stonehearth:build2:blueprint'):get_data()
         if stonehearth.building:has_data(d:get_bid()) then
            overlap[d:get_bid()] = stonehearth.building:get_data(d:get_bid())
         end
      end
   end
   return overlap
end

function mutation_utils._displace_rooms(mutated_data)
   if radiant.empty(mutated_data) then
      return
   end
   local rooms_by_level = {}

   for _, room in pairs(mutated_data) do
      local min_y = room:get_world_floor_shape():get_bounds().min.y
      local rooms = rooms_by_level[min_y]
      if not rooms then
         rooms = {}
         rooms_by_level[min_y] = rooms
      end

      rooms[room:get_bid()] = room
   end

   for _, rooms in pairs(rooms_by_level) do
      local current_rooms = mutation_utils._overlapping_rooms(rooms)

      -- Given moved rooms, and all the current (pre-mutated) rooms, do all of our
      -- displacements.
      mutation_utils._modify_rooms(rooms, current_rooms)
   end
end

function mutation_utils.add_room_holes(datum, holes_region_w)
   for id, data in pairs(datum) do
      stonehearth.building:mutate_data(data:add_hole(holes_region_w))
   end
end

local function _make_ready_to_move(all_displaced)
   local builders = BuilderCache()

   local all_displaced_and_fixtures = radiant.shallow_copy(all_displaced)
   for bid, _ in pairs(all_displaced) do
      local data = stonehearth.building:get_data(bid)
      radiant.append_map(all_displaced_and_fixtures, data:get_fixtures())
   end

   for bid, _ in pairs(all_displaced) do
      local builder = builders:get(bid)
      local data = builder:get_data()

      -- Remove each mover from everyone they mask, as long as those maskees are not themselves moving.
      for maskee_bid, _ in pairs(data:get_masked()) do
         if not all_displaced[maskee_bid] then
            local maskee = builders:get(maskee_bid)
            maskee:remove_mask(bid)
            builder:remove_masked(maskee_bid)
         end
      end
      -- Remove from each mover all non-mover maskers.
      for mask_bid, _ in pairs(data:get_masks()) do
         if not all_displaced_and_fixtures[mask_bid] then
            local mask = builders:get(mask_bid)
            builder:remove_mask(mask_bid)
            mask:remove_masked(bid)
         end
      end

      -- Remove each mover from everyone they support, as long as those supported are not themselves moving.
      for supportee_bid, _ in pairs(data:get_supported()) do
         if not all_displaced[supportee_bid] then
            local supportee = builders:get(supportee_bid)
            supportee:remove_support(bid)
            builder:remove_supported(supportee_bid)
         end
      end
      -- Remove from each mover all non-mover supports.
      for support_bid, _ in pairs(data:get_supports()) do
         if not all_displaced[support_bid] then
            local support = builders:get(support_bid)
            builder:remove_support(support_bid)
            support:remove_supported(bid)
         end
      end

      -- Remove each mover from everyone they support, as long as those supported are not themselves moving.
      for adjee_bid, _ in pairs(data:get_adjacent()) do
         if not all_displaced[adjee_bid] then
            local supportee = builders:get(adjee_bid)
            supportee:remove_adjacent(bid)
            builder:remove_adjacent(adjee_bid)
         end
      end
   end

   builders:flush()

   return all_displaced_and_fixtures
end

local function _calculate_perimeter_wall_supported(wall_datum, room_data, ignore_supported, include_adjacent)
   local results = {}
   local shape_w = wall_datum:get_world_shape()
   local ignore_bids = {[room_data:get_bid()] = true}

   local overlapping = _get_overlapping_data(room_data:get_building_id(), shape_w, ignore_bids)

   if not ignore_supported then
      local supports = _get_overlapping_data(room_data:get_building_id(), shape_w:translated(Point3(0, 1, 0)), ignore_bids)
      for other_bid in pairs(supports) do
         if not overlapping[other_bid] then
            if room_data:get_supports()[other_bid] then
               results[other_bid] = true
            end
         end
      end
   end

   if include_adjacent then
      for _, side in ipairs(_sides) do
         local adjacents = _get_overlapping_data(room_data:get_building_id(), shape_w:translated(side), ignore_bids)
         for other_bid, other_data in pairs(adjacents) do
            if not overlapping[other_bid] and other_data:get_uri() == BlocksData.URI then
               if room_data:get_adjacent()[other_bid] then
                  results[other_bid] = true
               end
            end
         end
      end
   end

   return results
end

local function _calculate_supports(datum, ignore_supported, include_adjacent)
   local supports = {}
   for _, data in pairs(datum) do
      if data:get_uri() == PerimeterWallData.URI then
         local room_data = stonehearth.building:get_data(data:get_room_id())
         radiant.append_map(supports, _calculate_perimeter_wall_supported(data, room_data, ignore_supported, include_adjacent))
      else

         if not ignore_supported then
            for s_bid, _ in pairs(data:get_supports()) do
               supports[s_bid] = true
            end
         end

         if include_adjacent then
            for s_bid, _ in pairs(data:get_adjacent()) do
               supports[s_bid] = true
            end
         end
      end
   end

   radiant.append_map(supports, _get_all_supported(supports))
   return supports
end

local function _displace(all_displaced, delta)
   if delta == Point3.zero then
      return
   end
   local rooms = {}
   for bid, _ in pairs(all_displaced) do
      -- Store the newly mutated data.
      local data = stonehearth.building:get_data(bid):move(delta)
      if data:get_uri() ~= RoomData.URI then
         stonehearth.building:mutate_data(data)
      else
         rooms[bid] = data
      end
   end
   mutation_utils._displace_rooms(rooms)
end

local function _mutate_deformation(op_fn, datum, include_adjacent, ignore_supported, ...)
   if radiant.empty(datum) then
      return
   end
   local all_displaced = {}

   -- If anything supported/adjacent is going to move, collect all required structures.
   if not ignore_supported or include_adjacent then
      all_displaced = _calculate_supports(datum, ignore_supported, include_adjacent)
   end

   -- All required + instigators(datum) need to have their supports/masks readied
   -- for the mutation.
   local all_displaced_and_datum = radiant.shallow_copy(_get_bids(datum))
   radiant.append_map(all_displaced_and_datum, all_displaced)
   local all_adjusted_and_fixtures = _make_ready_to_move(all_displaced_and_datum)

   -- Actually do the thing.
   local delta = op_fn(datum, ...)

   -- Move everyone that should have moved.
   _displace(all_displaced, delta)

   local _, newly_added = stonehearth.building:get_all_mutation_data()
   for id, d in pairs(newly_added) do
      all_displaced_and_datum[id] = d
   end

   -- Get all masks and supports correctly re-calculated.
   mutation_utils._post_mutate(all_displaced_and_datum, all_adjusted_and_fixtures)

   -- Calculate all the heavy stuff (masks, regions).
   local all_mutated, all_added, _ = stonehearth.building:get_all_mutation_data()
   for _, data in pairs(all_mutated) do
      data:deferred_build()
   end
   for _, data in pairs(all_added) do
      data:deferred_build()
   end
end

local function _voxel_extrude(bids, blocks, delta, adding)
   for bid, _ in pairs(bids) do
      local data = stonehearth.building:get_data(bid)
      local mut_data, new_datum = data:extrude(blocks, delta, adding)

      stonehearth.building:mutate_data(mut_data)
      for _, d in pairs(new_datum) do
         stonehearth.building:add_data(d)
      end
   end
   return Point3.zero
end

function mutation_utils.voxel_extrude(bids, blocks, delta, adding)
   local datum = _get_datum(bids)

   _mutate_deformation(
      _voxel_extrude,
      datum,
      false,
      true,
      blocks,
      delta,
      adding)
end

local function _voxel_add(bids, blocks_w, to_merge)
   local bid = radiant.first_key(bids)
   local data = stonehearth.building:get_data(bid)
   data = data:add_blocks(blocks_w)
   local origin = data:get_world_origin()

   for other_bid, _ in pairs(to_merge) do
      local other_data = stonehearth.building:get_data(other_bid)
      local fixtures = other_data:get_fixtures()
      for f_bid, _ in pairs(fixtures) do
         local fixture = stonehearth.building:get_data(f_bid)
         local f_origin = fixture:get_world_origin()

         -- Don't actually remove the fixtures, since we're going to blow away
         -- the entire voxel structure.
         -- other_data = other_data:remove_fixture(f_bid)
         data = data:add_fixture(f_bid)

         local new_fixture = fixture:move_to(bid, f_origin - origin, fixture:get_direction())
         stonehearth.building:mutate_data(new_fixture)

      end
      stonehearth.building:remove_data(other_data:remove(true))
   end

   stonehearth.building:mutate_data(data)

   return Point3.zero
end

function mutation_utils.voxel_add(bids, blocks_w, to_merge)
   local datum = _get_datum(bids)

   _mutate_deformation(
      _voxel_add,
      datum,
      false,
      true,
      blocks_w,
      to_merge)
end

local function _stretch_walls(datum, start, delta)
   for bid, _ in pairs(_get_bids(datum)) do
      local data = stonehearth.building:get_data(bid)
      stonehearth.building:mutate_data(data:stretch(start, delta))
   end
   return Point3(delta.x, 0, delta.y)
end

function mutation_utils.stretch_walls(bids, start, delta)
   local datum = _get_datum(bids)

   _mutate_deformation(
      _stretch_walls,
      datum,
      false,
      true,
      start,
      delta)
end

local function _rotate(datum)
   for _, data in pairs(datum) do
      local data = stonehearth.building:get_data(data:get_bid())
      stonehearth.building:mutate_data(data:rotate())
   end
   return Point3(0, 0, 0)
end

function mutation_utils.rotate(bids)
   _mutate_deformation(
      _rotate,
      _get_datum(bids),
      false,
      true)
end

local function _adjust_height(datum, delta_y)
   for _, data in pairs(datum) do
      if data:get_uri() == PerimeterWallData.URI then
         local room_data = stonehearth.building:get_data(data:get_room_id())
         stonehearth.building:mutate_data(room_data:adjust_wall_height(data:get_start(), data:get_end(), delta_y))
      else
         stonehearth.building:mutate_data(stonehearth.building:get_data(data:get_bid()):adjust_height(delta_y))
      end
   end

   return Point3(0, delta_y, 0)
end

function mutation_utils.adjust_height(datum, delta_y, ignore_supported)
   _mutate_deformation(
      _adjust_height,
      datum,
      false,
      ignore_supported,
      delta_y)
end

local function _adjust_offset(datum, delta_y)
   for bid, _ in pairs(_get_bids(datum)) do
      local data = stonehearth.building:get_data(bid)
      stonehearth.building:mutate_data(data:adjust_offset(delta_y))
   end

   return Point3(0, delta_y, 0)
end

function mutation_utils.adjust_offset(datum, delta_y)
   _mutate_deformation(
      _adjust_offset,
      datum,
      false,
      false,
      delta_y)
end

local function _move_perimeter_wall(datum, delta)

   -- The actual op
   local perimeter_wall = radiant.first(datum)
   local dir = delta + Point3.zero
   dir:normalize()
   local polygon = perimeter_wall:get_swept_area(delta.xz)
   local old_room_data = stonehearth.building:get_data(perimeter_wall:get_room_id())
   local mutated_rooms = {}
   mutated_rooms[old_room_data:get_bid()] = old_room_data

   if delta:dot(perimeter_wall:get_normal()) > 0 then
      mutated_rooms[old_room_data:get_bid()] = old_room_data:add_to_perimeter(polygon, perimeter_wall:get_start(), perimeter_wall:get_end(), delta.xz)
   else
      mutated_rooms[old_room_data:get_bid()] = old_room_data:subtract_from_perimeter(polygon, perimeter_wall:get_start(), perimeter_wall:get_end(), delta.xz)
   end

   local current_rooms = mutation_utils._overlapping_rooms(mutated_rooms)

   -- If the moved wall is shared, make sure we adjust the other room, too.
   local origin = old_room_data:get_origin()
   local p1 = perimeter_wall:get_start() + origin.xz
   local p2 = perimeter_wall:get_end() + origin.xz
   for current_room_bid, current_room in pairs(current_rooms) do
      if current_room_bid ~= old_room_data:get_bid() then
         local current_origin = current_room:get_origin().xz
         if current_room:get_perimeter():within(p1 - current_origin, p2 - current_origin) then
            local offset = origin.xz - current_origin
            p1 = p1 - current_origin
            p2 = p2 - current_origin
            if delta:dot(perimeter_wall:get_normal()) > 0 then
               current_rooms[current_room_bid] = current_room:subtract_from_perimeter(polygon:translated(offset), p1, p2, delta.xz)
            else
               current_rooms[current_room_bid] = current_room:add_to_perimeter(polygon:translated(offset), p1, p2, delta.xz)
            end

            -- A given wall can (must) only ever overlap with one other wall.
            break
         end
      end
   end
   mutation_utils._modify_rooms(mutated_rooms, current_rooms)

   return delta
end

function mutation_utils.move_perimeter_wall(datum, delta, ignore_supported)
   _mutate_deformation(
      _move_perimeter_wall,
      datum,
      true,
      ignore_supported,
      delta)
end

function mutation_utils.vertical_displace(bids, delta_y, ignore_supported)
   if delta_y == 0 then
      return
   end

   mutation_utils._displace(bids, Point3(0, delta_y, 0), ignore_supported)

   local all_mutated, all_added, _ = stonehearth.building:get_all_mutation_data()

   for _, data in pairs(all_mutated) do
      data:deferred_build()
   end
   for _, data in pairs(all_added) do
      data:deferred_build()
   end
end

function mutation_utils.displace(bids, delta, ignore_supported)
   if delta == Point3.zero then
      return
   end

   mutation_utils._displace(bids, delta, ignore_supported)

   local all_mutated, all_added, _ = stonehearth.building:get_all_mutation_data()

   for _, data in pairs(all_mutated) do
      data:deferred_build()
   end
   for _, data in pairs(all_added) do
      data:deferred_build()
   end
end

function mutation_utils._post_mutate(bids, ignored_bids)
   local builders = BuilderCache()

   local mutated, _, removed = stonehearth.building:get_all_mutation_data()

   -- Now that stuff has happened, remove all bids that were destroyed in this process.
   bids = _filter_removed(bids)

   -- Regenerate masks and supports.
   -- For everyone that moved, find out what the structure now overlaps, ignore things that moved.
   -- The structures now masks that.
   for bid, _ in pairs(bids) do
      local builder = builders:get(bid)
      local data = builder:get_data()

      local data_uri = data:get_uri()
      local ds = _get_overlapping_data(data:get_building_id(), data:get_world_shape(), ignored_bids, true)
      for other_bid, _ in pairs(ds) do
         local other = builders:get(other_bid)
         if other:get_data():get_uri() == FixtureData.URI and data_uri ~= FixtureData.URI then
            other:add_masked(bid)
            builder:add_mask(other_bid)
         elseif other:get_data():get_uri() ~= FixtureData.URI then
            other:add_mask(bid)
            builder:add_masked(other_bid)
         end
      end
   end

   -- Remove all contributions of 'removed' from masks.
   -- Don't touch the removed!  We need to preserve its bits for resurrection.
   for bid, data in pairs(removed) do
      for other_bid, _ in pairs(data:get_masked()) do
         if not removed[other_bid] then
            local other = builders:get(other_bid)
            other:remove_mask(bid)
         end
      end

      for other_bid, _ in pairs(data:get_masks()) do
         if not removed[other_bid] then
            local other = builders:get(other_bid)
            other:remove_masked(bid)
         end
      end

      for other_bid, _ in pairs(data:get_supported()) do
         if not removed[other_bid] then
            local other = builders:get(other_bid)
            other:remove_support(bid)
         end
      end

      for other_bid, _ in pairs(data:get_supports()) do
         if not removed[other_bid] then
            local other = builders:get(other_bid)
            other:remove_supported(bid)
         end
      end

      for other_bid, _ in pairs(data:get_adjacent()) do
         if not removed[other_bid] then
            local other = builders:get(other_bid)
            other:remove_adjacent(bid)
         end
      end
   end

   _recompute_supports(bids, builders)

   builders:flush()

   if not radiant.is_server then
      return
   end

   mutated, _, _ = stonehearth.building:get_all_mutation_data()

   local building_id
   if not radiant.empty(bids) then
      building_id = stonehearth.building:get_data(radiant.first_key(bids)):get_building_id()
   elseif not radiant.empty(mutated) then
      building_id = stonehearth.building:get_data(radiant.first_key(mutated)):get_building_id()
   end

   -- If we can't find a building from either the mutated or the supplied bids,
   -- then it must be the case that nothing changed in the building that could alter
   -- their validity.  So, don't bother if that's the case.
   if building_id then
      _recompute_validity(building_id)
   end
end

function mutation_utils._displace(bids, delta, ignore_supported)
   -- Get everyone that is going to move.
   local all_displaced = radiant.shallow_copy(bids)

   if not ignore_supported then
      radiant.append_map(all_displaced, _get_all_exclusively_supported(bids))
   end
   local all_displaced_and_fixtures = _make_ready_to_move(all_displaced)

   _displace(all_displaced, delta)

   mutation_utils._post_mutate(all_displaced, all_displaced_and_fixtures)
end

function mutation_utils.paint(datum, region_w)
   for bid, _ in pairs(datum) do
      local data = stonehearth.building:get_data(bid)
      stonehearth.building:mutate_data(data:paint(region_w):deferred_build())
   end
end

function _add_hole(bids, hole_w)
   for bid, _ in pairs(bids) do
      local data = stonehearth.building:get_data(bid)
      local mut_data, new_datum = data:add_hole(hole_w)
      stonehearth.building:mutate_data(mut_data)
      if new_datum then
         for _, d in pairs(new_datum) do
            stonehearth.building:add_data(d)
         end
      end
   end
   return Point3.zero
end

function mutation_utils.add_hole(bids, hole_w)
   local datum = _get_datum(bids)
   _mutate_deformation(
      _add_hole,
      datum,
      false,
      true,
      hole_w)
end

local function _displace_fixture(fixtures, to_bid, pos_w, direction, to_sub_bid)
   local bid = radiant.first(radiant.keys(fixtures))
   local fixture = stonehearth.building:get_data(bid)
   local from_bid = fixture:get_owner_bid()
   local from_data = from_bid ~= -1 and stonehearth.building:get_data(from_bid) or nil
   local to_data = to_bid ~= -1 and stonehearth.building:get_data(to_bid) or nil
   local to_origin = to_data and to_data:get_origin() or Point3.zero

   stonehearth.building:mutate_data(fixture:move_to(to_bid, pos_w - to_origin, direction, to_sub_bid))

   if from_bid == to_bid and from_data then
      stonehearth.building:mutate_data(from_data:add_fixture(bid, to_sub_bid))
   else
      if from_data then
         stonehearth.building:mutate_data(from_data:remove_fixture(bid))
      end

      if to_data then
         stonehearth.building:mutate_data(to_data:add_fixture(bid, to_sub_bid))
      end
   end

   return Point3(0, 0, 0)
end

function mutation_utils.displace_fixture(fixture, to_bid, pos_w, direction, to_sub_bid)
   local bids = {[fixture:get_bid()] = true}
   local datum = _get_datum(bids)

   _mutate_deformation(
         _displace_fixture,
         datum,
         false,
         true,
         to_bid,
         pos_w,
         direction,
         to_sub_bid)
end

local function _place_other(data)
   stonehearth.building:add_data(data)

   if data:get_uri() == FixtureData.URI then
      if data:get_owner_bid() ~= -1 then
         local owner = stonehearth.building:get_data(data:get_owner_bid())
         stonehearth.building:mutate_data(owner:add_fixture(data:get_bid(), data:get_owner_sub_bid()))
      end
   end
end

local function _place_room(room)
   local current_rooms = mutation_utils._overlapping_rooms({[room:get_bid()] = room})
   if room:is_fusing() then
      mutation_utils._fuse_rooms(room, current_rooms)
      return
   end


   -- Add the new room as a mutated room, in order to compute all the side effects
   -- of its presence; then, remove it from 'modified', because we really know that
   -- it is new.
   local mutated_data = {}
   mutated_data[room:get_bid()] = room
   mutation_utils._modify_rooms(mutated_data, current_rooms, true)
end

local function _create(fn, data)
   fn(data)
   local all_mutated, all_added, _ = stonehearth.building:get_all_mutation_data()

   local all = radiant.shallow_copy(all_mutated)
   radiant.append_map(all, all_added)

   mutation_utils._post_mutate(all_added, all_added)

   -- Calculate all the heavy stuff (masks, regions).
   all_mutated, all_added, _ = stonehearth.building:get_all_mutation_data()
   for _, data in pairs(all_mutated) do
      data:deferred_build()
   end
   for _, data in pairs(all_added) do
      data:deferred_build()
   end
end

function mutation_utils.create(data)
   if data:get_uri() == RoomData.URI then
      _create(_place_room, data)
   else
      _create(_place_other, data)
   end
end

local function _remove(datum)
   for _, data in pairs(datum) do
      if data:get_uri() == FixtureData.URI then
         local owner_bid = data:get_owner_bid()
         stonehearth.building:remove_data(data:remove())
         if owner_bid ~= -1 then
            stonehearth.building:mutate_data(stonehearth.building:get_data(owner_bid):remove_fixture(data:get_bid()))
         end
      else
         stonehearth.building:remove_data(data:remove())
      end
   end

   return Point3(0, 0, 0)
end

function mutation_utils.remove(bid, include_all_supported)
   local bids = {}
   bids[bid] = true

   if include_all_supported then
      radiant.append_map(bids, _get_all_exclusively_supported(bids))
   end

   local datum = _get_datum(bids)
   _mutate_deformation(
      _remove,
      datum,
      false,
      true)
end

local function _set_roof_drop_walls(datum, has_drop_walls)
   for bid, _ in pairs(datum) do
      local roof = stonehearth.building:get_data(bid)
      stonehearth.building:mutate_data(roof:set_has_drop_walls(has_drop_walls))
   end

   return Point3(0, -radiant.first(datum):get_offset(), 0)
end

function mutation_utils.set_roof_drop_walls(roofs, has_drop_walls)
   local roofs = _get_datum(roofs)
   _mutate_deformation(
      _set_roof_drop_walls,
      roofs,
      false,
      true,
      has_drop_walls)
end

local function _set_roof_gradients(datum, gradient, enabled)
   for bid, _ in pairs(_get_bids(datum)) do
      local roof = stonehearth.building:get_data(bid)
      stonehearth.building:mutate_data(roof:set_gradient(gradient, enabled))
   end

   -- TODO: not quite :P
   return Point3(0, 0, 0)
end

function mutation_utils.set_roof_gradients(roof, gradient, enabled)
   local roofs = { [roof:get_bid()] = roof }

   _mutate_deformation(
      _set_roof_gradients,
      roofs,
      false,
      true,
      gradient,
      enabled)
end

function mutation_utils._fuse_rooms(fuser, current_rooms)
   local interacted = {}
   local new_perimeter_w = fuser:get_perimeter_in(nil)
   for other_id, other_room in pairs(current_rooms) do
      if other_id ~= fuser:get_bid() then
         local other_perimeter_w = other_room:get_perimeter_in(nil)
         if other_perimeter_w:intersects(new_perimeter_w) then
            interacted[other_id] = other_room
         end
      end
   end

   if radiant.empty(interacted) then
      stonehearth.building:add_data(fuser:make_fusing(false))
   else
      -- Multi-room fusion: pick a winner, and merge everyone into it.
      local room_id, room = next(interacted)
      interacted[room_id] = nil
      room = room:fuse_room(fuser)

      for id, eaten_room in pairs(interacted) do
         stonehearth.building:remove_data(eaten_room:remove())
         room:dangerous_fuse_room(eaten_room)
      end
      stonehearth.building:mutate_data(room)
   end
end

-- Given a map of modified room_data, and a map of existing room_data, compute
-- all the changes that will happen to the existing rooms; output them as a map.
-- This is a nice, super-general function that knows nothing about displacement,
-- perimeter walls moving, or whatever.  It just takes in to account the entirety of
-- the new modified room's shape when computing mutations, so it is ALWAYS right.
function mutation_utils._modify_rooms(modified_rooms, current_rooms, is_adding_room)
   local interacted = {}
   local interacted_ordered = {}
   local interacted_modified = {}
   -- Record what rooms are presently touched.
   for id, modified_room in pairs(modified_rooms) do
      local original_perimeter_w
      if current_rooms[id] then
         original_perimeter_w = current_rooms[id]:get_perimeter_in(nil)
      elseif is_adding_room then
         original_perimeter_w = modified_room:get_perimeter_in(nil)
      end

      if original_perimeter_w then
         local new_perimeter_w = modified_room:get_perimeter_in(nil)
         for other_id, other_room in pairs(current_rooms) do
            if not modified_rooms[other_id] then
               local other_perimeter_w = other_room:get_perimeter_in(nil)
               if other_perimeter_w:intersects(original_perimeter_w) or other_perimeter_w:intersects(new_perimeter_w) then
                  interacted[other_id] = other_room
                  interacted_modified[id] = modified_room
               end
            end
         end
      end
   end

   -- First, we can just run and mutate all the modified rooms that are
   -- NOT interacting with anything.
   for bid, room in pairs(modified_rooms) do
      if not interacted_modified[bid] then
         if is_adding_room then
            stonehearth.building:add_data(room)
         else
            stonehearth.building:mutate_data(room:simplified())
         end
      end
   end


   -- Order all the interactions; in particular, the explicitly modified
   -- come last, so that they will 'win' all the modifications.
   for _, room in pairs(interacted) do
      table.insert(interacted_ordered, room)
   end
   for _, room in pairs(interacted_modified) do
      table.insert(interacted_ordered, room)
   end

   local simplified_perimeters = {}
   for _, room in ipairs(interacted_ordered) do
      table.insert(simplified_perimeters, room:get_perimeter_in(nil):simplified())
   end

   -- Do the actual mutations.
   local new_perimeters = {}
   for idx, room in ipairs(interacted_ordered) do
      local perimeter = simplified_perimeters[idx]
      for idx2, other_room in ipairs(interacted_ordered) do
         if idx ~= idx2 then
            local other_perimeter = simplified_perimeters[idx2]
            if other_perimeter:intersects(perimeter) and room:get_world_shape():intersects_region(other_room:get_world_shape()) then
               -- Avoid doing intersections that annihilate the entire room....
               if not perimeter:within_polygon(other_perimeter) then
                  perimeter = perimeter:sub(other_perimeter)[1]
               end
            end
         end
      end

      assert(perimeter)
      simplified_perimeters[idx] = perimeter
   end

   for idx, room in ipairs(interacted_ordered) do
      room = room:apply_polygon(simplified_perimeters[idx]:translated(-room:get_world_origin().xz))

      if is_adding_room and modified_rooms[room:get_bid()] then
         stonehearth.building:add_data(room)
      else
         stonehearth.building:mutate_data(room)
      end
   end
end

function mutation_utils.split_wall(room_bid, split_pos)
   local room = stonehearth.building:get_data(room_bid)
   local local_split_pos = split_pos - room:get_world_origin()

   stonehearth.building:mutate_data(room:split_wall(local_split_pos.xz):deferred_build())
end

function mutation_utils.set_roof_brushes(roof, roof_brush, wall_brush, column_brush)
   stonehearth.building:mutate_data(roof:set_brushes(roof_brush, wall_brush, column_brush):deferred_build())
end

function mutation_utils.set_roof_brush(roof, roof_brush)
   stonehearth.building:mutate_data(roof:set_brushes(roof_brush, roof:get_wall_brush(), roof:get_column_brush()):deferred_build())
end

function mutation_utils.set_stairs_brushes(stairs, stairs_brush)
   stonehearth.building:mutate_data(stairs:set_brushes(stairs_brush):deferred_build())
end

function mutation_utils.set_wall_brush(wall, brush)
   stonehearth.building:mutate_data(wall:set_brush(brush):deferred_build())
end

function mutation_utils.set_perimeter_wall_brush(owner, p1, p2, brush)
   stonehearth.building:mutate_data(owner:set_wall_brush(p1, p2, brush):deferred_build())
end

function mutation_utils.set_column_brush(wall, brush)
   stonehearth.building:mutate_data(wall:set_column_brush(brush):deferred_build())
end

function mutation_utils.set_floor_brush(room, brush)
   stonehearth.building:mutate_data(room:set_floor_brush(brush):deferred_build())
end

function mutation_utils.set_perimeter_column_brush(owner, p1, p2, brush)
   stonehearth.building:mutate_data(owner:set_column_brush(p1, p2, brush):deferred_build())
end

function mutation_utils.set_stairs_style(stairs, style)
   stonehearth.building:mutate_data(stairs:set_style(style):deferred_build())
end

function mutation_utils.set_all_room_wall_brushes(room, brush)
   stonehearth.building:mutate_data(room:set_all_wall_brushes(brush):deferred_build())
end

function mutation_utils.set_all_room_column_brushes(room, brush)
   stonehearth.building:mutate_data(room:set_all_column_brushes(brush):deferred_build())
end

function mutation_utils.set_all_roof_wall_brushes(roof, brush)
   stonehearth.building:mutate_data(roof:set_all_wall_brushes(brush):deferred_build())
end

function mutation_utils.set_all_roof_column_brushes(roof, brush)
   stonehearth.building:mutate_data(roof:set_all_column_brushes(brush):deferred_build())
end

function mutation_utils.recompute_supports(bids)
   local builders = BuilderCache()
   for bid, _ in pairs(bids) do
      _recompute_supports({[bid] = true}, builders)
   end
   builders:flush()
end

return mutation_utils
