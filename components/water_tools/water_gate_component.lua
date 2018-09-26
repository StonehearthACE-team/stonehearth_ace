local log = radiant.log.create_logger('water_gate')

local WaterGateComponent = class()

function WaterGateComponent:activate()
	-- just add a listener to see when we get enabled or disabled
	self._enabled_listener = radiant.events.listen(self._entity, 'stonehearth_ace:enabled_changed', self, self._on_enabled_changed)
end

function WaterGateComponent:destroy()
	if self._enabled_listener then
		self._enabled_listener:destroy()
		self._enabled_listener = nil
	end
end

function WaterGateComponent:_on_enabled_changed(enabled)
	local new_collision_type = enabled and 'enabled' or 'disabled'
	self._entity:add_component('stonehearth_ace:entity_modification'):set_region_collision_type(new_collision_type)
end

return WaterGateComponent
