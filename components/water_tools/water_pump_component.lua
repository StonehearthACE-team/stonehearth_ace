local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_tools')

local WaterPumpComponent = class()

function WaterPumpComponent:initialize()
	self._tick_listener = nil
end

function WaterPumpComponent:create()
	local json = radiant.entities.get_json(self)
	self._sv.rate = math.max(json and json.rate or 1, 0)
	self._sv.depth = math.max(json and json.depth or 0, 0)
	self._sv.height = math.max(json and json.height or 1, 1)
	self._sv.topper_region = json.topper_region and Region3(radiant.util.to_cube3(json.topper_region))
	self._sv._pump_child_entity = nil
	self.__saved_variables:mark_changed()
end

function WaterPumpComponent:restore()
	self._is_restore = true
end

function WaterPumpComponent:activate()
	--Trace the parent to figure out if it's added or not:
	self._parent_trace = self._entity:add_component('mob'):trace_parent('water pump added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
						:on_changed(function(parent_entity)
								if not parent_entity then
									--we were just removed from the world
									self:_shutdown()
								else
									--we were just added to the world
									self:_startup()
								end
							end)
	
	self._location_trace = self._entity:add_component('mob'):trace_transform('water pump moved', _radiant.dm.TraceCategories.SYNC_TRACE)
                           :on_changed(function()
                                 self:_startup()
                              end)
end

function WaterPumpComponent:post_activate()
	self._enabled = self._entity:get_component('stonehearth_ace:toggle_enabled')
	self._container = self._entity:get_component('stonehearth_ace:container')
	self:_startup()

	if self._is_restore then
		self._parent_trace:push_object_state()
	end
end

function WaterPumpComponent:destroy()
   --When the water tool is destroyed, destroy any other child entities
   self:_shutdown()
end

function WaterPumpComponent:_startup()
	self._sv.location = radiant.entities.get_world_grid_location(self._entity)
	if not self._sv.location then
		log:error('could not get location of water pump')
		return
	end
	if not self._sv._pump_child_entity then
		-- if we don't already have a child entity for this pump, create it
		self._entity:add_component('stonehearth_ace:entity_modification'):set_region3('region_collision_shape', 'region_with_topper')
		self._sv._pump_child_entity = radiant.entities.create_entity('stonehearth_ace:gizmos:water_pump_topper', { owner = self._entity })
		if self._sv.topper_region then
			self._sv._pump_child_entity:add_component('stonehearth_ace:entity_modification'):set_region3('region_collision_shape', self._sv.topper_region)
		end
		radiant.terrain.place_entity_at_exact_location(self._sv._pump_child_entity, self._sv.location)
		self.__saved_variables:mark_changed()
	else
		-- make sure the child entity is properly positioned
		radiant.terrain.place_entity_at_exact_location(self._sv._pump_child_entity, self._sv.location)
	end

	stonehearth_ace.water_pump:register_water_pump(self, self._sv.location.y)
end

function WaterPumpComponent:_shutdown()
	stonehearth_ace.water_pump:unregister_water_pump(self)
	
	-- if we have a child entity for this pump, delete it
	if self._sv._pump_child_entity then
		radiant.entities.destroy_entity(self._sv._pump_child_entity)
		self._sv._pump_child_entity = nil
		self._entity:add_component('stonehearth_ace:entity_modification'):reset_region3('region_collision_shape')
	end
	self._sv.location = nil
	self.__saved_variables:mark_changed()
end

function WaterPumpComponent:get_location()
	return self._sv.location
end

function WaterPumpComponent:get_entity_id()
	return self._entity:get_id()
end

function WaterPumpComponent:get_rate()
	return self._sv.rate
end

function WaterPumpComponent:set_rate(value)
	self._sv.rate = math.max(value, 0)
	self.__saved_variables:mark_changed()
end

function WaterPumpComponent:get_height()
	return self._sv.height
end

function WaterPumpComponent:get_depth()
	return self._sv.depth
end

function WaterPumpComponent:set_depth(value)
	self._sv.depth = math.max(value, 0)
	self.__saved_variables:mark_changed()
end

function WaterPumpComponent:_on_tick_water_pump()
	if not self._enabled or not self._enabled:get_enabled() or self._sv.rate <= 0 then
		return
	end

	local location = radiant.entities.get_world_grid_location(self._entity)
	if not location then
		return
	end
	
	-- identify the destination for the water
	local output_location = location + Point3(0, self:get_height(), 0)

	local rate = self._sv.rate

	-- we want to take water from the pump's container, or if lacking, from the world at its location (or lower depth)
	-- if possible, this water will go into the world (or a destination container)
	-- whatever amount we fail to place (should be rare) we put back in our container

	local volume_not_removed = rate
	if self._container then
		volume_not_removed = self._container:remove_volume('stonehearth:water', volume_not_removed)
	end

	if volume_not_removed > 0 then
		-- pull water up from the lowest depth first
		for depth = self._sv.depth, 0, -1 do
			local source_location = location + Point3(0, -depth, 0)
			local water_body = self:_get_water_body(source_location)

			if water_body then
				-- try removing water from this depth
				volume_not_removed = stonehearth.hydrology:remove_water(volume_not_removed, source_location, water_body)
			end

			if volume_not_removed <= 0 then
				break
			end
		end
	end

	local amount_to_add = rate - volume_not_removed
	local volume_not_added
	
	local destination_container, is_solid = self:_get_destination_container(output_location)
	if destination_container then
		volume_not_added = destination_container:add_volume('stonehearth:water', amount_to_add)
	else
		-- check to see if the output_location block is solid; if it is, don't pump anything
		if is_solid then
			volume_not_added = amount_to_add
		else
			volume_not_added = stonehearth.hydrology:add_water(amount_to_add, output_location)
		end
	end

	if volume_not_added > 0 then
		if self._container then
			self._container:add_volume('stonehearth:water', volume_not_added)
		else
			stonehearth.hydrology:add_water(volume_not_added, location)
		end
	end
end

function WaterPumpComponent:_get_water_body(location)
	if not location then
		return nil
	end

	local entities = radiant.terrain.get_entities_at_point(location)

	for id, entity in pairs(entities) do
		local water_component = entity:get_component('stonehearth:water')
		if water_component then
			return entity
		end
	end

	return nil
end

function WaterPumpComponent:_get_destination_container(location)
	if not location then
		return nil, false
	end

	local entities = radiant.terrain.get_entities_at_point(location)

	local container_component = nil
	local is_solid = false

	for id, entity in pairs(entities) do
		local container = entity:get_component('stonehearth_ace:container')
		if container and container:get_type() == 'stonehearth:water' then
			container_component = container
		end
		if entity:add_component('region_collision_shape'):get_region_collision_type() == _radiant.om.RegionCollisionShape.SOLID then
			is_solid = true
		end
	end

	return container_component, is_solid
end

return WaterPumpComponent
