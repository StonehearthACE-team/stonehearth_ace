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
	self._sv.depth = math.max(json and json.depth or 0, 0)
	self._sv._pump_child_entity = nil
	self.__saved_variables:mark_changed()
	
	self:set_height(json and json.height or 2)
end

function WaterToolsComponent:restore()
	self._is_restore = true
end

function WaterToolsComponent:activate()
	--Trace the parent to figure out if it's added or not:
	self._parent_trace = self._entity:add_component('mob'):trace_parent('water tool added or removed', _radiant.dm.TraceCategories.SYNC_TRACE)
						:on_changed(function(parent_entity)
								if not parent_entity then
									--we were just removed from the world
									self:_shutdown()
								else
									--we were just added to the world
									self:_startup()
								end
							end)
	
	self._location_trace = self._entity:add_component('mob'):trace_transform('water tool moved', _radiant.dm.TraceCategories.SYNC_TRACE)
                           :on_changed(function()
                                 self:_startup()
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
		self._sv.location = radiant.entities.get_world_grid_location(self._entity)
		if not self._sv.location then
			log:error('could not get location of water pump')
			return
		end
		local child_location = self._sv.location + Point3(0, self:get_base_height(), 0)

		if not self._sv._pump_child_entity then
			-- if we don't already have a child entity for this pump, create it
			self._entity:add_component('stonehearth_ace:entity_modification'):set_region3s('region_collision_shape', 'region_with_topper')
			self._sv._pump_child_entity = radiant.entities.create_entity('stonehearth_ace:gizmos:water_pump_topper', { owner = self._entity })
			radiant.terrain.place_entity_at_exact_location(self._sv._pump_child_entity, child_location)
		else
			-- make sure the child entity is properly positioned
			radiant.terrain.place_entity_at_exact_location(self._sv._pump_child_entity, child_location)
		end
		self.__saved_variables:mark_changed()

		stonehearth_ace.water_pump:register_water_pump(self, self._sv.location.y)
	end
end

function WaterToolsComponent:_shutdown()
	if self._sv.type == 'water_pump' then
		-- if we have a child entity for this pump, delete it
		if self._sv._pump_child_entity then
			radiant.entities.destroy_entity(self._sv._pump_child_entity)
			self._sv._pump_child_entity = nil
			self._entity:add_component('stonehearth_ace:entity_modification'):reset_region3s('region_collision_shape')
		end
		self._sv.location = nil
		self.__saved_variables:mark_changed()

		stonehearth_ace.water_pump:unregister_water_pump(self)
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
		local new_collision_type = self._sv.enabled and 'enabled' or 'disabled'
		
		self._entity:add_component('stonehearth_ace:entity_modification'):set_region_collision_type(new_collision_type)
	end

	-- do anything else here like playing animations?
end

function WaterToolsComponent:get_type()
	return self._sv.type
end

function WaterToolsComponent:get_location()
	return self._sv.location
end

function WaterToolsComponent:get_entity_id()
	return self._entity:get_id()
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

function WaterToolsComponent:get_base_height()
	return self._sv.height - 1
end

function WaterToolsComponent:get_height()
	return self._sv.height
end

function WaterToolsComponent:set_height(value)
	self._sv.height = math.max(value, 2)
	self._sv.storage_queue = {}
	for i = 1, self._sv.height - 1, 1 do
		table.insert(self._sv.storage_queue, 0)
	end

	self.__saved_variables:mark_changed()
end

function WaterToolsComponent:get_depth()
	return self._sv.depth
end

function WaterToolsComponent:set_depth(value)
	self._sv.depth = math.max(value, 0)
	self.__saved_variables:mark_changed()
end

function WaterToolsComponent:add_water(volume)
	if volume <= 0 then
		return 0
	end
	
	local add_volume = 0

	-- if there's room, add water directly into the storage queue
	if #self._sv.storage_queue < self:get_height() then
		add_volume = math.min(volume, self._sv.rate)
		table.insert(self._sv.storage_queue, add_volume)
	elseif #self._sv.storage_queue == self:get_height() then
		add_volume = math.min(volume, self._sv.rate - self._sv.storage_queue[#self._sv.storage_queue])
		self._sv.storage_queue[#self._sv.storage_queue] = self._sv.storage_queue[#self._sv.storage_queue] + add_volume
	end

	return volume - add_volume
end

function WaterToolsComponent:_on_tick_water_pump(destination_pump)
	if not self._sv.enabled or self._sv.rate <= 0 then
		return
	end

	local location = radiant.entities.get_world_grid_location(self._entity)
	if not location then
		return
	end
	
	-- identify the destination for the water
	local output_location = location + Point3(0, self:get_height(), 0)

	local rate = self._sv.rate
	local total_volume_in = 0

	-- we want to move water upwards through the pump, starting at the top (in the storage_queue)
	-- if possible, this water will go into the world (or a destination_pump); we need to pop the top and try to place it
	-- whatever amount we fail to place (should be rare) we add to the next available spot where there's room
	-- if there's no room, subtract the failed amount from the amount we're trying to pull in

	local amount = table.remove(self._sv.storage_queue, 1)
	local volume_not_added
	
	if destination_pump then
		volume_not_added = destination_pump:add_water(amount)
	else
		volume_not_added = stonehearth.hydrology:add_water(amount, output_location)
	end

	if volume_not_added > 0 then
		amount = amount - volume_not_added
		for i = 1, #self._sv.storage_queue, 1 do
			if self._sv.storage_queue[i] < rate then
				local space = rate - self._sv.storage_queue[i]
				local amount_to_add = math.min(volume_not_added, space)
				self._sv.storage_queue[i] = math.min(self._sv.storage_queue[i] + amount_to_add, rate)
				volume_not_added = volume_not_added - amount_to_add
			end

			if volume_not_added <= 0 then
				break
			end
		end
	end

	rate = rate - volume_not_added

	if rate > 0 then
		-- pull water up from the lowest depth first
		for depth = self._sv.depth, 0, -1 do
			local source_location = location + Point3(0, -depth, 0)
			local water_body = self:_get_water_body(source_location)

			if water_body then
				-- first we need to remove water from the source
				local volume_not_removed = stonehearth.hydrology:remove_water(rate - total_volume_in, source_location, water_body)
				local volume_removed = rate - volume_not_removed
				total_volume_in = total_volume_in + volume_removed
			end

			if total_volume_in >= rate then
				break
			end
		end
	end

	-- finally we need to store the water we pulled in in our storage_queue
	table.insert(self._sv.storage_queue, total_volume_in + volume_not_added)

	log:error('water pump removed %d water and added %d water', total_volume_in, amount - volume_not_added)
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
