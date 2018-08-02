local ShepherdPastureComponent = require 'stonehearth.components.shepherd_pasture.shepherd_pasture_component'
local AceShepherdPastureComponent = class()
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

AceShepherdPastureComponent._old_destroy = ShepherdPastureComponent.destroy
function AceShepherdPastureComponent:destroy()
	self:_old_destroy()

	-- destroy the add_grass timer and also destroy any grass entities in the pasture
	self:_destroy_grass_spawn_timer()

end

AceShepherdPastureComponent._old_set_size = ShepherdPastureComponent.set_size
function AceShepherdPastureComponent:set_size(x, z)
	self:_old_set_size(x, z)

	-- spawn a few grass if possible
	-- determine the amount of grass in the pasture and use that instead of the total area
	
	local num_to_spawn = x * z / 200

	if self._is_create then
		for i = 1, num_to_spawn do
			self:_spawn_grass()
		end
	end
end

function AceShepherdPastureComponent:_find_grass_spawn_points()
	
	local kind = radiant.terrain.get_block_kind_at(location)
end

AceShepherdPastureComponent._old__create_pasture_tasks = ShepherdPastureComponent._create_pasture_tasks
function AceShepherdPastureComponent:_create_pasture_tasks()
	self:_old__create_pasture_tasks()

	-- set up grass spawning timer
	self:_setup_grass_spawn_timer()
end

function AceShepherdPastureComponent:_setup_grass_spawn_timer()
	self:_destroy_grass_spawn_timer()
	
	-- determine spawn rate (based on number of animals)


	self._spawn_grass_timer = stonehearth.calendar:set_interval('spawn grass')
end

function AceShepherdPastureComponent:_destroy_grass_spawn_timer()
	if self._spawn_grass_timer then
		self._spawn_grass_timer:destroy()
		self._spawn_grass_timer = nil
	end
end

function AceShepherdPastureComponent:_spawn_grass()
	-- try to find an unoccupied space in the bounds; if 20 attempts fail, oh well, don't spawn it

end

return AceShepherdPastureComponent
