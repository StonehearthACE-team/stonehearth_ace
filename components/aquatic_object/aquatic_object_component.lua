local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3

local AquaticObjectComponent = class()

function AquaticObjectComponent:initialize()
	self._sv.in_the_water = nil
	self._sv.original_y = nil
	self.__saved_variables:mark_changed()
end

function AquaticObjectComponent:activate()
	local json = radiant.entities.get_json(self)
	self._require_water_to_grow = json.require_water_to_grow
	self._destroy_if_out_of_water = json.destroy_if_out_of_water
	self._floating_object = json.floating_object
	self:_create_listeners()
	self:_on_water_exists_changed()
	self:_on_water_surface_level_changed()
end

function AquaticObjectComponent:_create_listeners()
	if not self._water_listener then
		self._water_listener = radiant.events.listen(self._entity, 'stonehearth_ace:water_signal:water_exists_changed', self, self._on_water_exists_changed)
	end
	if not self._water_surface_level_listener then
		self._water_surface_level_listener = radiant.events.listen(self._entity, 'stonehearth_ace:water_signal:water_surface_level_changed', self, self._on_water_surface_level_changed)
	end
end

function AquaticObjectComponent:_on_water_exists_changed(exists)
	if exists == nil then
		exists = self._entity:add_component('stonehearth_ace:water_signal'):get_water_exists()
	end

	self._sv.in_the_water = exists
	self.__saved_variables:mark_changed()

	if self._require_water_to_grow then
		self:timers_resume(exists)
	end
	-- do whatever else you want to have happen when its "in water" status changes
	-- perhaps add a buff and create a timer to kill something if it's out of water (and cancel the buff and timer if it's back in)?
end

function AquaticObjectComponent:_on_water_surface_level_changed(level)
	if level == nil then
		level = self._entity:add_component('stonehearth_ace:water_signal'):get_water_surface_level()
	end

	if self._floating_object then
		self:float(level)
	end
end

function AquaticObjectComponent:float(level)
	if not self._floating_object then
		return
	end
   
	local vertical_offset = self._floating_object.vertical_offset or 0
	local location = self._sv.original_y
	if not location then
		location = radiant.entities.get_world_grid_location(self._entity)
		self._sv.original_y = location
		self.__saved_variables:mark_changed()
	end
	if level then
		location = location + level + vertical_offset
	end
	radiant.entities.move_to(self._entity, location)
	self._entity:add_component('mob'):set_ignore_gravity(level ~= nil)
end

function AquaticObjectComponent:timers_resume(resume)
	local renewable_resource_node_component = self._entity:get_component('stonehearth:renewable_resource_node')
	local evolve_component = self._entity:get_component('stonehearth:evolve')
	local growing_component = self._entity:get_component('stonehearth:growing')
	
	if renewable_resource_node_component then
		if resume then
			renewable_resource_node_component:resume_resource_timer()
		else
			renewable_resource_node_component:pause_resource_timer()
		end
	end
	
	if evolve_component then
		if resume then
			evolve_component:start_evolve_timer()
		else
			evolve_component:stop_evolve_timer()
		end
	end
	
	if growing_component then
		if resume then
			growing_component:start_growing()
		else
			growing_component:stop_growing()
		end
	end
end

function AquaticObjectComponent:destroy()
	self:_destroy_listeners()
end

function AquaticObjectComponent:_destroy_listeners()
	if self._water_listener then
		self._water_listener:destroy()
		self._water_listener = nil
	end
	if self._water_surface_level_listener then
		self._water_surface_level_listener:destroy()
		self._water_surface_level_listener = nil
	end
end

return AquaticObjectComponent
