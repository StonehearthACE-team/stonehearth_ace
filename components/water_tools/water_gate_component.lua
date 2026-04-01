local log = radiant.log.create_logger('water_gate')

local WaterGateComponent = class()

function WaterGateComponent:activate()
	self._json = radiant.entities.get_json(self) or {}

	-- just add a listener to see when we get enabled or disabled
	self._enabled_listener = radiant.events.listen(self._entity, 'stonehearth_ace:enabled_changed', self, self._on_enabled_changed)
	self._type = self._json.type or 'default'
end

function WaterGateComponent:destroy()
	if self._enabled_listener then
		self._enabled_listener:destroy()
		self._enabled_listener = nil
	end
end

function WaterGateComponent:_on_enabled_changed(enabled)
	local collision_change = enabled and 'enabled' or 'disabled'
	local entity_modification_comp = self._entity:add_component('stonehearth_ace:entity_modification')

	-- Change model
	if self._json.enabled_model then
		if enabled then
			entity_modification_comp:set_model_variant(self._json.enabled_model, false)
		else
			entity_modification_comp:reset_model_variant()
		end
	end

	if self._type == 'region_change' then
		if enabled then
			entity_modification_comp:set_region3('region_collision_shape', collision_change)
		else
			entity_modification_comp:reset_region3('region_collision_shape')
		end
	else
		entity_modification_comp:set_region_collision_type(collision_change)
	end
end

return WaterGateComponent
