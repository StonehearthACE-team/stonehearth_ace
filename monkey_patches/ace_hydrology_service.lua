local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local HydrologyService = require 'stonehearth.services.server.hydrology.hydrology_service'
local AceHydrologyService = class()

local log = radiant.log.create_logger('hydrology')

AceHydrologyService._ace_old__create_tick_timer = HydrologyService._create_tick_timer
function AceHydrologyService:_create_tick_timer()
   self:_ace_old__create_tick_timer()

   -- make sure the ACE water signal service is up and running (mainly a fix for stupid microworlds)
   stonehearth_ace.water_signal:start()
end

AceHydrologyService._ace_old__on_terrain_changed = HydrologyService._on_terrain_changed
function AceHydrologyService:_on_terrain_changed(delta_region, now)
   --log:debug('_on_terrain_changed...')

   if self._ignore_terrain_region then
      delta_region:subtract_region(self._ignore_terrain_region)
      self._ignore_terrain_region = nil
   end

   if not delta_region:empty() then
      --log:debug('... %s (%s), %s', delta_region, delta_region:get_bounds(), now)
      self:_ace_old__on_terrain_changed(delta_region, now)
   end
end

function AceHydrologyService:add_ignore_terrain_region_changes(region)
   if not self._ignore_terrain_region then
      self._ignore_terrain_region = Region3()
   end
   
   self._ignore_terrain_region:add_region(region)
end

function AceHydrologyService:_ensure_water_processors()
   if not self._water_processors then
      -- instead of always sorting a list, use elevation as a key and process from min to max
      self._water_processor_buckets = {}	-- contains all the water processors, grouped into buckets by elevation
      self._water_processors = {}	-- contains all the water processors with references to their elevation
      self._min_elevation = nil
      self._max_elevation = nil
   end
end

function AceHydrologyService:register_water_processor(entity_id, water_processor, elevation)
   self:_ensure_water_processors()

	-- adjust min and max elevation as necessary	
	if self._min_elevation then
		self._min_elevation = math.min(self._min_elevation, elevation)
	else
		self._min_elevation = elevation
	end

	if self._max_elevation then
		self._max_elevation = math.max(self._max_elevation, elevation)
	else
		self._max_elevation = elevation
	end
		
	-- keep a list of processors by their id so we can find their elevation to remove them from their bucket later
	self._water_processors[entity_id] = elevation
		
	-- if we don't already have a bucket for this elevation, add one
	local bucket = self._water_processor_buckets[elevation]
	if not bucket then
		self._water_processor_buckets[elevation] = {}
	end
	self._water_processor_buckets[elevation][entity_id] = water_processor
end

function AceHydrologyService:unregister_water_processor(entity_id, water_processor)
	self:_ensure_water_processors()
   
   if not water_processor or not entity_id then
		return
	end

	local elevation = self._water_processors[entity_id]
	if elevation then
		self._water_processors[entity_id] = nil
		local bucket = self._water_processor_buckets[elevation]
		bucket[entity_id] = nil
		if next(bucket) == nil then
			self._water_processor_buckets[elevation] = nil
		end
	end
end

-- TODO: if there's a way we can handle this in a more integrated way
-- and hold off on actually adding/removing water from both water processors
-- and natural water flow channels, instead creating a list of net changes
-- (or storing pre-changes in water/waterfall/water_sponge components),
-- and then perform only the net changes at the end of the tick (in the appropriate order)
-- it could greatly improve performance for static/closed systems
-- the flexibility of water processors makes that a lot trickier though
function AceHydrologyService:_process_water_processors()
	if not (self._min_elevation and self._max_elevation) then
		return
	end
	
   self:_ensure_water_processors()

   local new_min, new_max
   local all_water_processors = {}

	for elevation = self._max_elevation, self._min_elevation, -1 do
		local bucket = self._water_processor_buckets[elevation]
		if bucket and next(bucket) then
			if not new_max then
				new_max = elevation
			end
			new_min = elevation

			for _, water_processor in pairs(bucket) do
            water_processor:on_tick_water_processor()
            table.insert(all_water_processors, water_processor)
			end
		end
   end
   
   for _, water_processor in ipairs(all_water_processors) do
      water_processor:reset_processed_this_tick()
   end
	
	self._min_elevation = new_min
	self._max_elevation = new_max
end

function AceHydrologyService:_on_tick()
   log:spam('Start tick')

   --self:_update_performance_counters()
   log:spam('Processing unlinked waterfalls')
   self._sv._channel_manager:process_unlinked_waterfalls()
   log:spam('Updating channels')
   self._sv._channel_manager:update_all_channels()
   log:spam('Processing water queue')
   self:_process_water_queue()
   log:spam('ACE: Processing water pumps')
   self:_process_water_processors()
   log:spam('Merging water bodies')
   self:_check_for_channel_merge()
   log:spam('Evaporating water')
   self:_evaporate_from_water_bodies()

   self:_destroy_empty_water_bodies()
   self:_update_oscillation_counts()

   -- ACE: changed to trigger immediately, not async, so we can then immediately check if entities have changed
   radiant.events.trigger(self, 'stonehearth:hydrology:tick')
   self:_check_changed()

   log:spam('End tick')
   self.__saved_variables:mark_changed()
end

function AceHydrologyService:_check_changed()
   for id, entity in pairs(self._sv._water_bodies) do
      local water_component = entity:add_component('stonehearth:water')
      water_component:check_changed()
   end
end

-- ACE: remove max y cap on terrain bounds
function AceHydrologyService:_link_channels_for_block(point, entity)
   local channel_manager = self:get_channel_manager()
   local world_bounds = radiant.terrain.get_terrain_component():get_bounds()
   world_bounds.max.y = stonehearth.constants.terrain.MAX_Y_OVERRIDE

   for _, direction in ipairs(csg_lib.XYZ_DIRECTIONS) do
      local adjacent_point = point + direction
      if world_bounds:contains(adjacent_point) then
         local adjacent_is_solid = self._water_tight_region:contains(adjacent_point)
         if not adjacent_is_solid then
            local adjacent_entity = self:get_water_body_at(adjacent_point)
            if adjacent_entity then
               if adjacent_entity ~= entity then
                  channel_manager:add_pressure_channel_bidirectional(point, adjacent_point, entity, adjacent_entity)
               end
            else
               if direction.y ~= 1 then
                  channel_manager:add_waterfall_channel(point, adjacent_point, entity, nil)
               elseif entity:add_component('stonehearth:water'):get_water_level() > adjacent_point.y then
                  -- upwards waterfalls not supported
                  --channel_manager:add_waterfall_channel(point, adjacent_point, entity, nil)
               end
            end
         end
      end
   end
end

-- Optimized path to create a water body that is already filled.
-- Does not check that region is contained by a watertight boundary.
-- Know what you are doing before calling this.
-- ACE: merge_adjacent option for landmark placement: check for water entities that would connect to this region; after creation, merge them
function AceHydrologyService:create_water_body_with_region(region, height, merge_adjacent)
   assert(not region:empty())

   local water_entities = {}
   if merge_adjacent then
      local water_bodies = self._sv._water_bodies
      local expanded_region = csg_lib.get_non_diagonal_xyz_inflated_region(region)
      local entities = radiant.terrain.get_entities_in_region(expanded_region)
      
      for id, entity in pairs(entities) do
         local water_component = entity:get_component('stonehearth:water')
         if water_component and water_bodies[id] then
            table.insert(water_entities, entity)
         end
      end
   end

   local boxed_region = _radiant.sim.alloc_region3()
   local location = self:select_origin_for_region(region)

   -- water regions shouldn't have tags!
   local tagless_region = Region3()
   for cube in region:each_cube() do
      tagless_region:add_cube(Cube3(cube.min, cube.max, 0))
   end

   tagless_region:optimize('create_water_body_with_region')

   boxed_region:modify(function(cursor)
         cursor:copy_region(tagless_region)
         cursor:translate(-location)
      end)

   local water_entity = self:_create_water_body_internal(location, boxed_region, height)

   if merge_adjacent and next(water_entities) then
      log:debug('debug: merging water bodies %s with %s', radiant.util.table_tostring(water_entities), water_entity)
      for _, adjacent_water in ipairs(water_entities) do
         water_entity = self:merge_water_bodies(water_entity, adjacent_water, true)
      end

      -- make sure that after any merges it updates the region
      -- this function is usually not called during a tick, and if it is, it should only be once for that entity
      water_entity:get_component('stonehearth:water'):check_changed(true)
   end

   return water_entity
end

AceHydrologyService._ace_old__create_water_body_internal = HydrologyService._create_water_body_internal
function AceHydrologyService:_create_water_body_internal(location, boxed_region, height)
   log:debug('creating water body: %s, %s (%s), %s', location, tostring(boxed_region), boxed_region and boxed_region:get():get_bounds() or 'nil', tostring(height))
   return self:_ace_old__create_water_body_internal(location, boxed_region, height)
end

-- ACE: add extra parameter for skipping mark_changed
-- entity is an optional hint, returns volume of water that could not be added
function AceHydrologyService:add_water(volume, location, entity, skip_mark_changed)
   if volume <= 0 then
      return volume, nil
   end
   local initialize = true
   if not entity then
      entity = self:get_or_create_water_body_at(location)
   end
   local water_component = entity:add_component('stonehearth:water')
   local volume, info = water_component:add_water(volume, location)
   if not skip_mark_changed then
      water_component:check_changed(true)
   end

   if volume > 0 then
      if info.result == 'merge' then
         local master = self:merge_water_bodies(entity, info.entity)
         -- add the remaining water to the master
         local merge_occurred = true
         local volume, info = self:add_water(volume, location, master)
         return volume, info, merge_occurred
      else
         log:detail('could not add water because: %s', info.reason)
      end
   end
   return volume, info
end

-- ACE: add extra parameter for skipping mark_changed
-- must specify either location or entity, returns volume of water that could not be removed
function AceHydrologyService:remove_water(volume, location, entity, skip_mark_changed)
   if not entity then
      entity = self:get_water_body_at(location)
   end

   if not entity then
      return volume
   end

   local water_component = entity:add_component('stonehearth:water')
   local volume = water_component:remove_water(volume)
   if not skip_mark_changed then
      water_component:check_changed(true)
   end

   return volume
end

-- ACE: ignore from_entities that don't have water components
function AceHydrologyService:_choose_bounded_merge_partner(entity)
   local channel_manager = self._sv._channel_manager
   local partner_water_level
   local partner

   channel_manager:each_link_to(entity, function(link)
         local candidate = link.from_entity
            if candidate:get_component('stonehearth:water') then
            if self:_can_perform_bounded_merge(candidate, entity) then
               local candidate_water_level = candidate:add_component('stonehearth:water'):get_water_level()
               if not partner_water_level or candidate_water_level > partner_water_level then
                  partner = candidate
                  partner_water_level = candidate_water_level
               end
            end
         end
      end)

   return partner
end

-- ACE: ignore from_entities that don't have water components
function AceHydrologyService:_check_for_channel_merge()
   local channel_manager = self._sv._channel_manager

   repeat
      local restart = false
      channel_manager:each_link(function(link)
         if not channel_manager:link_has_channels(link) then
            return false
         end
         local entity1 = link.from_entity
         if entity1:get_component('stonehearth:water') then
            local entity2 = link.to_entity
            local can_merge, allow_uneven_merge = self:can_merge_water_bodies(entity1, entity2)
            if can_merge then
               self:merge_water_bodies(entity1, entity2, allow_uneven_merge)
               restart = true
               return true -- stop iteration
            end
            return false
         end
      end)
   until not restart
end

-- if you remove something from the water and want it to replace water there instead of adjusting/filling
-- returns true if successful, false if prefill function failed, and nil if not exactly one adjacent water region
function AceHydrologyService:auto_fill_water_region(region, prefill_fn)
   local inflated_region = csg_lib.get_non_diagonal_xyz_inflated_region(region)
   local waters = radiant.terrain.get_entities_in_region(inflated_region, function(entity) return entity:get_component('stonehearth:water') ~= nil end)
   local num_waters = radiant.size(waters)

   log:debug('considering auto-filling region %s with %s neighboring water regions', region:get_bounds(), num_waters)
   if num_waters == 1 then
      self:add_ignore_terrain_region_changes(region)
   end

   if prefill_fn and not prefill_fn(waters) then
      return false
   end

   -- eventually it would be cool if we could handle more than one water entity intersecting the region at different points
   if num_waters ~= 1 then
      return nil
   end

   local water_entity = waters[next(waters)]
   local water_comp = water_entity:get_component('stonehearth:water')
   local water_location = water_comp:get_location()
   local water_region = water_comp:get_region():get():translated(water_location)
   local water_level = water_comp:get_water_level()
   log:debug('found adjacent water region %s (%s) with water level %s', water_region, water_region:get_bounds(), water_level)

   -- use the bounds of the region to clip the top down to the water level
   local new_region = Region3(region)
   local bounds = new_region:get_bounds()
   local water_max_y = water_region:get_bounds().max.y
   local region_max_y = bounds.max.y
   local region_min_y = bounds.min.y
   log:debug('prepping %s (%s) and adding water to world height %s', region, bounds, water_level)

   if region_min_y > water_max_y then
      -- the entire region is above the water; just return
      log:debug('region %s above water %s; canceling fill', bounds, water_region:get_bounds())
      return nil
   elseif region_max_y > water_max_y then
      -- first we shift the bounds up by the height of the region, then down by the difference in region and water heights
      new_region = new_region - bounds:translated(Point3(0, water_max_y - region_min_y, 0))
      log:debug('region higher than water; reducing bounds to %s', new_region:get_bounds())
   end

   --local new_height = math.min(water_level, region_max_y) - region_min_y
   log:debug('adding region %s (%s) to water body %s', new_region, new_region:get_bounds(), water_entity)
   new_region:translate(-water_location)
   water_comp:add_to_region(new_region)
   --local new_water = self:create_water_body_with_region(new_region, new_height)
   -- merge the new water with the old
   --self:merge_water_bodies(water_entity, new_water, true)

   return true
end

return AceHydrologyService