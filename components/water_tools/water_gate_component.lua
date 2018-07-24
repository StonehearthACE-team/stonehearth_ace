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
	if self._closed_effect then
		self._closed_effect:stop()
		self._closed_effect = nil
	end
	if self._opened_effect then
		self._opened_effect:stop()
		self._opened_effect = nil
	end
end

function WaterGateComponent:_on_enabled_changed(enabled)
	local new_collision_type = enabled and 'enabled' or 'disabled'
	self._entity:add_component('stonehearth_ace:entity_modification'):set_region_collision_type(new_collision_type)

	-- JohnnyTendo's experiment:
	if enabled then
		self:_opened_gate()
	else
		self:_closed_gate()
	end
end

function WaterGateComponent:_opened_gate()
   if self._closed_effect then
      self._closed_effect:stop()
      self._closed_effect = nil
   end
   if not self._opened_effect then
      self._opened_effect = radiant.effects.run_effect(self._entity, 'opened')
         :set_cleanup_on_finish(false)
   end
end

function WaterGateComponent:_closed_gate()
   if self._opened_effect then
      self._opened_effect:stop()
      self._opened_effect = nil
   end
   if not self._closed_effect then
      self._closed_effect = radiant.effects.run_effect(self._entity, 'closed')
         :set_cleanup_on_finish(false)
   end
end

return WaterGateComponent
