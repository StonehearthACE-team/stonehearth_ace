local ShepherdPastureComponent = require 'stonehearth.components.shepherd_pasture.shepherd_pasture_component'
local AceShepherdPastureComponent = class()
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('shepherd_pasture')

-- for some reason, overriding the destroy function doesn't work, so we have to override this one that only gets called during destroy
AceShepherdPastureComponent._old__unregister_with_town = ShepherdPastureComponent._unregister_with_town
function AceShepherdPastureComponent:_unregister_with_town()
	self:_old__unregister_with_town()

	-- destroy the add_grass timer and also destroy any grass entities in the pasture
	self:_destroy_grass_spawn_timer()
	self:_destroy_grass()
end

function AceShepherdPastureComponent:_destroy_grass()
	local grass_uri = self:_get_grass_uri()
	local filter_fn = function(entity)
		return string.sub(entity:get_uri(), 1, string.len(grass_uri)) == grass_uri
	end

	local size = self:get_size()
	local world_loc = radiant.entities.get_world_grid_location(self._entity)
	local cube = Cube3(world_loc, world_loc + Point3(size.x, 1, size.z))
	local region = Region3(cube)
	local entities = radiant.terrain.get_entities_in_region(region, filter_fn)

	for _, e in pairs(entities) do
		radiant.terrain.remove_entity(e)
	end
end

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

	-- set up grass spawning timer
	self:_setup_grass_spawn_timer()
end

function AceShepherdPastureComponent:_setup_grass_spawn_timer()
	-- if the timer already existed, we want to consider the time spent to really be spent
	local time_remaining = nil
	if self._sv._grass_spawn_timer then
		local old_duration = self._sv._grass_spawn_timer:get_duration()
		local old_expire_time = self._sv._grass_spawn_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration
		local growth_period = self:_get_base_grass_spawn_period()
	  
		local old_progress = self:_get_current_growth_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv.grass_growth_recalculate_progress = old_progress + new_progress
		time_remaining = math.max(0, growth_period * (1 - self._sv.grass_growth_recalculate_progress))
	end
	local scaled_time_remaining = self:_calculate_grass_spawn_period(time_remaining)
	
	self:_destroy_grass_spawn_timer()
	self._sv._grass_spawn_timer = stonehearth.calendar:set_interval('spawn grass', scaled_time_remaining, function() self:_spawn_grass() end)
end

function AceShepherdPastureComponent:_destroy_grass_spawn_timer()
	if self._sv._grass_spawn_timer then
		self._sv._grass_spawn_timer:destroy()
		self._sv._grass_spawn_timer = nil
	end
end

function AceShepherdPastureComponent:_get_current_growth_recalculate_progress()
	return self._sv.grass_growth_recalculate_progress or 0
end

function AceShepherdPastureComponent:_calculate_grass_spawn_period(growth_period)
	if not growth_period then
		growth_period = self:_get_base_grass_spawn_period()
	end
	return stonehearth.town:calculate_growth_period(self._entity:get_player_id(), growth_period)
end

function AceShepherdPastureComponent:_get_base_grass_spawn_period()
	local spawn_period = radiant.entities.get_json(self).grass_spawn_period or '11h+2h'
	return stonehearth.calendar:parse_duration(spawn_period)
end

function AceShepherdPastureComponent:_spawn_grass(count, grass)
	if not count then
		count = math.ceil(math.sqrt(self:get_num_animals()))
	end
	if count < 1 then
		return
	end
	if not grass then
		grass = self:_find_grass_spawn_points()
	end
	if #grass < 1 then
		return
	end
	
	local grass_uri = self:_get_spawn_grass_uri()

	local rng = _radiant.math.get_default_rng()
	for i = 1, math.min(#grass, count) do
		-- try to find an unoccupied space in the bounds; if 20 attempts fail, oh well, don't spawn it
		for attempt = 1, math.min(#grass, 20) do
			local location = grass[rng:get_int(1, #grass)] + Point3(0, 1, 0)
			if self:_is_valid_grass_spawn_location(location) then
				-- we found a spot, spawn some grass
				local grass_entity = radiant.entities.create_entity(grass_uri, {owner = self._entity})
				local random_facing = rng:get_int(0, 3) * 90
				radiant.terrain.place_entity(grass_entity, location, { force_iconic = false, facing = random_facing })
				break
			end
		end
	end
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
