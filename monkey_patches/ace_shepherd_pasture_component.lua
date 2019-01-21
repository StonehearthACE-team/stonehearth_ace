local ShepherdPastureComponent = require 'stonehearth.components.shepherd_pasture.shepherd_pasture_component'
local AceShepherdPastureComponent = class()
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('shepherd_pasture')
local WEATHER_CHECK_TIME = '05:30am+2h' -- one hour after weather service has changed the weather
local DEFAULT_GRASS_SPAWN_RATE = '11h+2h'

AceShepherdPastureComponent._old_activate = ShepherdPastureComponent.activate
function AceShepherdPastureComponent:activate()
	self:_old_activate()
	self._weather_check_alarm = stonehearth.calendar:set_alarm(WEATHER_CHECK_TIME, radiant.bind(self, '_recalculate_duration'))
end

-- for some reason, overriding the destroy function doesn't work, so we have to override this one that only gets called during destroy
AceShepherdPastureComponent._old__unregister_with_town = ShepherdPastureComponent._unregister_with_town
function AceShepherdPastureComponent:_unregister_with_town()
	self:_old__unregister_with_town()

	-- destroy the add_grass timer and also destroy any grass entities in the pasture
	self:_destroy_grass_spawn_timer()
	self:_destroy_grass()

	if self._weather_check_alarm then
		self._weather_check_alarm:destroy()
		self._weather_check_alarm = nil
	end
end

function AceShepherdPastureComponent:_destroy_grass()
	local entities = self:_find_all_grass()

	for _, e in pairs(entities) do
		radiant.terrain.remove_entity(e)
	end
end

function AceShepherdPastureComponent:_find_all_grass()
   local grass_uri = self:_get_grass_uri()
	local filter_fn = function(entity)
		return string.sub(entity:get_uri(), 1, string.len(grass_uri)) == grass_uri
	end

	local size = self:get_size()
	local world_loc = radiant.entities.get_world_grid_location(self._entity)
	local cube = Cube3(world_loc, world_loc + Point3(size.x, 1, size.z))
	local region = Region3(cube)
	return radiant.terrain.get_entities_in_region(region, filter_fn)
end

-- called by the shepherd service once the field is created
function AceShepherdPastureComponent:post_creation_setup()
	-- spawn a few grass if possible
	-- determine the amount of grass in the pasture and use that instead of the total area
	local grass = self:_find_grass_spawn_points()
	local num_to_spawn = #grass / 200
	self:_spawn_grass(num_to_spawn, grass)
end

function AceShepherdPastureComponent:_find_grass_spawn_points()
	local grass = {}
	local size = self:get_size()
	local world_loc = radiant.entities.get_world_grid_location(self._entity)
	for x = 1, size.x do
		for z = 1, size.z do
			local location = world_loc + Point3(x - 1, -1, z - 1)
			local kind = radiant.terrain.get_block_kind_at(location)
			if kind == 'grass' then
				table.insert(grass, location)
			end
		end
	end

	return grass
end

AceShepherdPastureComponent._old__create_pasture_tasks = ShepherdPastureComponent._create_pasture_tasks
function AceShepherdPastureComponent:_create_pasture_tasks()
	self:_old__create_pasture_tasks()
	self:_start_grass_spawn()
end

function AceShepherdPastureComponent:_start_grass_spawn()
	if not self._sv._grass_spawn_timer then
		self:_setup_grass_spawn_timer()
	else
		-- if the timer already existed, we want to consider the time spent to really be spent
		self:_recalculate_duration()
	end
end

function AceShepherdPastureComponent:_setup_grass_spawn_timer()
	local spawn_period = self:_calculate_grass_spawn_period()
	self._sv._grass_spawn_timer = stonehearth.calendar:set_persistent_timer("AceShepherdPasture spawn grass", spawn_period, radiant.bind(self, '_spawn_grass'))
end

function AceShepherdPastureComponent:_destroy_grass_spawn_timer()
	if self._sv._grass_spawn_timer then
		self._sv._grass_spawn_timer:destroy()
		self._sv._grass_spawn_timer = nil
	end
end

function AceShepherdPastureComponent:_recalculate_duration()
	if self._sv._grass_spawn_timer then
		local old_duration = self._sv._grass_spawn_timer:get_duration()
		local old_expire_time = self._sv._grass_spawn_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration

		local spawn_period = self:_get_base_grass_spawn_period()
		local old_progress = self:_get_current_spawn_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv._grass_spawn_recalculate_progress = old_progress + new_progress
		local time_remaining = math.max(0, spawn_period * (1 - self._sv._grass_spawn_recalculate_progress))
		local scaled_time_remaining = self:_calculate_grass_spawn_period(time_remaining)
		self:_destroy_grass_spawn_timer()
		self._sv._grass_spawn_timer = stonehearth.calendar:set_persistent_timer("AceShepherdPasture spawn grass", scaled_time_remaining, radiant.bind(self, '_spawn_grass'))
	end
end

function AceShepherdPastureComponent:_get_current_spawn_recalculate_progress()
	return self._sv._grass_spawn_recalculate_progress or 0
end

function AceShepherdPastureComponent:_calculate_grass_spawn_period(spawn_period)
	if not spawn_period then
		spawn_period = self:_get_base_grass_spawn_period()
	end
	-- This applies weather, biome, and town vitality multipliers
	spawn_period = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), spawn_period)
	return spawn_period
end

function AceShepherdPastureComponent:_apply_season_multiplier(spawn_period)
	return spawn_period
end

function AceShepherdPastureComponent:_get_base_grass_spawn_period()
	local spawn_period = radiant.entities.get_json(self).grass_spawn_period or DEFAULT_GRASS_SPAWN_RATE
	return stonehearth.calendar:parse_duration(spawn_period)
end

function AceShepherdPastureComponent:_spawn_grass(count, spawn_locations)
	if not count then
		count = math.ceil(math.sqrt(self:get_num_animals()))
	end
	if count < 1 then
		return
   end

	if not spawn_locations then
		spawn_locations = self:_find_grass_spawn_points()
	end
	if #spawn_locations < 1 then
		return
   end
   
   local existing_grass = self:_find_all_grass()
   local grass_count = radiant.size(existing_grass)
   count = math.min(count, math.sqrt(#spawn_locations) - grass_count)
   if count < 1 then
      return
   end
	
	local grass_uri = self:_get_spawn_grass_uri()

	local rng = _radiant.math.get_default_rng()
	for i = 1, math.min(#spawn_locations, count) do
		-- try to find an unoccupied space in the bounds; if 5 attempts fail, oh well, don't spawn it
      for attempt = 1, math.min(count, 5) do
         -- remove the location from our list of possibles as we try it, so we don't keep retrying invalid spaces
         -- because it's either already invalid or will become invalid once we spawn grass there
			local location = table.remove(spawn_locations, rng:get_int(1, #spawn_locations)) + Point3(0, 1, 0)
			if self:_is_valid_grass_spawn_location(location) then
				-- we found a spot, spawn some grass
				local grass_entity = radiant.entities.create_entity(grass_uri, {owner = self._entity})
				local random_facing = rng:get_int(0, 3) * 90
				radiant.terrain.place_entity(grass_entity, location, { force_iconic = false, facing = random_facing })
            break
         end
         
         if #spawn_locations < 1 then
            break
         end
      end
      
      if #spawn_locations < 1 then
         break
      end
	end

	self:_setup_grass_spawn_timer()
end

function AceShepherdPastureComponent:_get_grass_uri()
	return radiant.entities.get_json(self).grass_uri or 'stonehearth_ace:terrain:pasture_grass'
end

function AceShepherdPastureComponent:_get_spawn_grass_uri()
	return radiant.entities.get_json(self).spawn_grass_uri or 'stonehearth_ace:terrain:pasture_grass:sprouting'
end

function AceShepherdPastureComponent:_is_valid_grass_spawn_location(location)
	local filter_fn = function(entity)
		return entity ~= self._entity
	end
	return not next(radiant.terrain.get_entities_at_point(location, filter_fn))
end

-- overrides original to only create harvest task if auto-harvest is enabled for them
function AceShepherdPastureComponent:_create_harvest_task(target)
   local renewable_resource_component = target:get_component('stonehearth:renewable_resource_node')
   local player_id = self._entity:get_player_id()
   if renewable_resource_component and -- renewable_resource_component:get_auto_harvest_enabled() then
         (player_id == '' or stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'enable_auto_harvest_animals', true)) then
      renewable_resource_component:request_harvest(player_id)
   end
end

return AceShepherdPastureComponent
