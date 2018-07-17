local csg_lib = require 'lib.csg.csg_lib'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_tools')

local WaterToolsComponent = class()

-- Closely mimics wet_stone_component.lua and firepit_component.lua
function WaterToolsComponent:initialize()
	self._tick_listener = nil
end

function WaterToolsComponent:create()
	local json = radiant.entities.get_json(self)
	self._sv.enabled = false or json.enabled
	self._sv.type = json.type
	self._sv.on_command = json.on_command
	self._sv.off_command = json.off_command
	self._sv.rate = math.max(json and json.rate or 1, 0)
	self._sv.height = math.max(json and json.height or 1, 1)
	self._sv.depth = math.max(json and json.depth or 0, 0)
	self._sv._pump_child_entity = nil
	self.__saved_variables:mark_changed()
end

function WaterToolsComponent:restore()
	self._is_restore = true
end

function WaterToolsComponent:activate()
	--Trace the parent to figure out if it's added or not:
	self._parent_trace = self._entity:add_component('mob'):trace_parent('water tool added or removed')
						:on_changed(function(parent_entity)
								if not parent_entity then
									--we were just removed from the world
									self:_shutdown()
								else
									--we were just added to the world
									self:_startup()
								end
							end)
end

function WaterToolsComponent:post_activate()
	self:_on_enabled_changed()
	self:_startup()

	if self._is_restore then
		self._parent_trace:push_object_state()
	end
end

function WaterToolsComponent:destroy()
   --When the water tool is destroyed, destroy any other child entities
   self:_shutdown()
end

function WaterToolsComponent:_startup()
	if self._sv.type == 'water_pump' then
		local location = radiant.entities.get_world_grid_location(self._entity)
		if not location then
			log:error('could not get location of water pump')
			return
		end
		location = Point3(location) + Point3(0, self:get_height(), 0)

		if not self._sv._pump_child_entity then
			-- if we don't already have a child entity for this pump, create it
			self._sv._pump_child_entity = radiant.entities.create_entity('stonehearth_ace:gizmos:water_pump_topper', { owner = self._entity })
			radiant.terrain.place_entity_at_exact_location(self._sv._pump_child_entity, location)
		else
			-- make sure the child entity is properly positioned
			radiant.terrain.place_entity_at_exact_location(self._sv._pump_child_entity, location)
		end
		self.__saved_variables:mark_changed()
	end

	if not self._tick_listener then
		self._tick_listener = radiant.events.listen(stonehearth.hydrology, 'stonehearth:hydrology:tick', function()
			self:_on_tick()
		end)
	end
end

function WaterToolsComponent:_shutdown()
	if self._sv.type == 'water_pump' then
		-- if we have a child entity for this pump, delete it
		if self._sv._pump_child_entity then
			radiant.entities.destroy_entity(self._sv._pump_child_entity)
			self._sv._pump_child_entity = nil
		end
	end

	if self._tick_listener then
		self._tick_listener:destroy()
		self._tick_listener = nil
	end
end

function WaterToolsComponent:_on_enabled_changed()
	-- swap commands
	local commands_component = self._entity:get_component('stonehearth:commands')
	if commands_component then
		if self._sv.enabled then
			commands_component:remove_command(self._sv.on_command)
			if not commands_component:has_command(self._sv.off_command) then
				commands_component:add_command(self._sv.off_command)
			end
		else
			commands_component:remove_command(self._sv.off_command)
			if not commands_component:has_command(self._sv.on_command) then
				commands_component:add_command(self._sv.on_command)
			end
		end
	end

	if self._sv.type == 'water_gate' then
		local new_collision_type
		if self._sv.enabled then
			new_collision_type = _radiant.om.RegionCollisionShape.PLATFORM
		else
			new_collision_type = _radiant.om.RegionCollisionShape.SOLID
		end

		self._entity:get_component('region_collision_shape'):set_region_collision_type(new_collision_type)
	end

	-- do anything else here like playing animations?
end

function WaterToolsComponent:get_type()
	return self._sv.type
end

function WaterToolsComponent:get_enabled()
	return self._sv.enabled
end

function WaterToolsComponent:set_enabled(value)
	if self._sv.enabled ~= value then
		self._sv.enabled = value
		self.__saved_variables:mark_changed()

		self:_on_enabled_changed()

		radiant.events.trigger(radiant, 'stonehearth_ace:on_water_tools_enabled_changed', { entity = self._entity, enabled = value })
	end
end

function WaterToolsComponent:get_rate()
	return self._sv.rate
end

function WaterToolsComponent:set_rate(value)
	self._sv.rate = math.max(value, 0)
	self.__saved_variables:mark_changed()
end

function WaterToolsComponent:get_height()
	return self._sv.height
end

function WaterToolsComponent:get_output_height()
	return self._sv.height + 1
end

function WaterToolsComponent:set_height(value)
	self._sv.height = math.max(value, 1)
	self.__saved_variables:mark_changed()
end

function WaterToolsComponent:get_depth()
	return self._sv.depth
end

function WaterToolsComponent:set_depth(value)
	self._sv.depth = math.max(value, 0)
	self.__saved_variables:mark_changed()
end

function WaterToolsComponent:destroy()
	if self._tick_listener then
		self._tick_listener:destroy()
		self._tick_listener = nil
	end
end

function WaterToolsComponent:_on_tick()
	if self._sv.type == 'water_pump' then
		self:_on_tick_water_pump()
	end
end

function WaterToolsComponent:_on_tick_water_pump()
	if not self._sv.enabled or self._sv.rate <= 0 then
		return
	end

	local location = radiant.entities.get_world_grid_location(self._entity)
	if not location then
		return
	end
	
	-- identify the destination for the water
	local output_location = location + Point3(0, self:get_output_height(), 0)

	local rate = self._sv.rate
	local total_volume_in = 0

	-- pull water up from the lowest depth first
	for depth = self._sv.depth, 0, -1 do
		local source_location = location + Point3(0, -depth, 0)
		local water_body = self:_get_water_body(source_location)

		if water_body then
			-- first we need to remove water from where the entity is
			local volume_not_removed, info = stonehearth.hydrology:remove_water(rate - total_volume_in, source_location, water_body)
			local volume_removed = rate - volume_not_removed
			total_volume_in = total_volume_in + volume_removed

			-- then we need to try adding the same amount of water that was removed to a position above the entity
			local volume_not_added, info = stonehearth.hydrology:add_water(volume_removed, output_location)

			log:debug('water pump removed %d water and added %d water', volume_removed, volume_removed - volume_not_added)

			-- finally, if we output less volume than we input, output the difference back at the source location
			if volume_not_added > 0 then
				stonehearth.hydrology:add_water(volume_not_added, source_location, water_body)
				break
			end
		end

		if total_volume_in >= rate then
			break
		end
	end
end

function WaterToolsComponent:_get_water_body(location)
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

return WaterToolsComponent
