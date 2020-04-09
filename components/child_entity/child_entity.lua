local Point3 = _radiant.csg.Point3
local ChildEntity = class()

function ChildEntity:initialize()
	self._sv.children = {}
	self.__saved_variables:mark_changed()
end

function ChildEntity:activate()
	self.json_child_list = radiant.entities.get_json(self)

	if not self._added_to_world_listener then
		self._added_to_world_listener = radiant.events.listen(self._entity, 'stonehearth:on_added_to_world', function()
			self:on_added_to_world()
		end)
	end
	if not self._removed_from_world_listener then
		self._removed_from_world_listener = radiant.events.listen(self._entity, 'stonehearth:on_removed_from_world', function()
			self:on_removed_from_world()
		end)
	end
end

function ChildEntity:on_added_to_world()
	local delayed_function = function ()
		--for some reason, location is still nil when the on_added event fires,
		--so we wait 1gametick for it to be set, and it is done running inside this
		local location = radiant.entities.get_world_grid_location(self._entity)
		local facing = radiant.entities.get_facing(self._entity)

		for uri, data in pairs(self.json_child_list) do
			local child = radiant.entities.create_entity(uri,
				{owner = self._entity:get_player_id()})
			local rotate = data.facing or 0
			radiant.entities.turn_to(child, facing +rotate)
			local offset = data.offset and Point3(data.offset.x, data.offset.y, data.offset.z) or Point3.zero
			radiant.terrain.place_entity_at_exact_location(child, location +offset, {force_iconic = false})

			table.insert(self._sv.children, child)
		end

		self.__saved_variables:mark_changed()
		self.stupid_delay:destroy()
		self.stupid_delay = nil
	end
	self.stupid_delay = stonehearth.calendar:set_persistent_timer("ChildEntity delay", 0, delayed_function)
end

function ChildEntity:on_removed_from_world()
	for i,v in ipairs(self._sv.children) do
		radiant.entities.destroy_entity(v)
	end
	self._sv.children = {}
	self.__saved_variables:mark_changed()
end

function ChildEntity:destroy()
	self:on_removed_from_world()
	if self._added_to_world_listener then
		self._added_to_world_listener:destroy()
		self._added_to_world_listener = nil
	end
	if self._removed_from_world_listener then
		self._removed_from_world_listener:destroy()
		self._removed_from_world_listener = nil
	end
end

return ChildEntity