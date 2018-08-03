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
		return entity:get_uri() == grass_uri
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
	self:_destroy_grass_spawn_timer()
	
	local grass_spawn_period = radiant.entities.get_json(self).grass_spawn_period or '11h+2h'
	self._grass_spawn_timer = stonehearth.calendar:set_interval('spawn grass', grass_spawn_period, function() self:_spawn_grass() end)
end

function AceShepherdPastureComponent:_destroy_grass_spawn_timer()
	if self._grass_spawn_timer then
		self._grass_spawn_timer:destroy()
		self._grass_spawn_timer = nil
	end
end

function AceShepherdPastureComponent:_spawn_grass(count, grass)
	if not count then
		count = math.ceil(self:get_num_animals() / 2)
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
	
	local grass_uri = self:_get_grass_uri()

	local rng = _radiant.math.get_default_rng()
	for i = 1, count do
		-- try to find an unoccupied space in the bounds; if 20 attempts fail, oh well, don't spawn it
		for attempt = 1, math.min(#grass, 20) do
			local location = grass[rng:get_int(1, #grass)] + Point3(0, 1, 0)
			if self:_is_valid_grass_spawn_location(location) then
				-- we found a spot, spawn some grass
				local grass_entity = radiant.entities.create_entity(grass_uri)
				local random_facing = rng:get_int(0, 3) * 90
				radiant.terrain.place_entity(grass_entity, location, { force_iconic = false, facing = random_facing })
				break
			end
		end
	end
end

function AceShepherdPastureComponent:_get_grass_uri()
	return radiant.entities.get_json(self).grass_uri or 'stonehearth_ace:terrain:pasture_grass:sprouting'
end

function AceShepherdPastureComponent:_is_valid_grass_spawn_location(location)
	local filter_fn = function(entity)
		return entity ~= self._entity
	end
	return not next(radiant.terrain.get_entities_at_point(location, filter_fn))
end

return AceShepherdPastureComponent
