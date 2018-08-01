local calendar = stonehearth.calendar
local TrainingDummyComponent = class()

function TrainingDummyComponent:initialize()
	self._json = radiant.entities.get_json(self) or {}
	self._sv.enabled = true
	self._sv.combat_time = calendar:realtime_to_game_seconds(self._json.combat_time or 5)
	self._sv.disable_health_percentage = self._json.disable_health_percentage or 0.3
	self.__saved_variables:mark_changed()
end

function TrainingDummyComponent:create()
	self._is_create = true
end

function TrainingDummyComponent:activate()
	self._health_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:health', self, self._on_health_changed)
end

function TrainingDummyComponent:destroy()
	if self._health_listener then
		self._health_listener:destroy()
		self._health_listener = nil
	end

	self:_destroy_combat_timer()
end

function TrainingDummyComponent:_destroy_combat_timer()
	if self._sv._combat_timer then
		self._sv._combat_timer:destroy()
		self._sv._combat_timer = nil
	end
end

function TrainingDummyComponent:get_enabled()
	return self._sv.enabled
end

function TrainingDummyComponent:_disable()
	self._sv.enabled = false
	self:_destroy_combat_timer()
	self:_reset_combat_state()
	self.__saved_variables:mark_changed()
end

function TrainingDummyComponent:_enable()
	self._sv.enabled = true
	self.__saved_variables:mark_changed()
end

function TrainingDummyComponent:set_in_combat()
	self._entity:add_component('stonehearth:combat_state'):set_primary_target(self._entity)
	self:_refresh_combat_timer()
end

function TrainingDummyComponent:_refresh_combat_timer()
	self._sv._entered_combat_time = calendar:get_elapsed_time()
	if not self._sv._combat_timer then
		self:_create_combat_timer(self._sv.combat_time)
	end
end

function TrainingDummyComponent:_on_combat_timer()
	self:_destroy_combat_timer()

	-- check if we've been out of combat for long enough
	local current_time = calendar:get_elapsed_time()
	local ooc_time = (self._sv._entered_combat_time or 0) + self._sv.combat_time
	if ooc_time <= current_time then
		self:_reset_combat_state()
	else
		self:_create_combat_timer(ooc_time - current_time)
	end
end

function TrainingDummyComponent:_reset_combat_state()
	self._entity:add_component('stonehearth:combat_state'):set_primary_target(nil)
end

function TrainingDummyComponent:_create_combat_timer(ooc_time)
	self._sv._combat_timer = calendar:set_timer('training dummy combat', ooc_time, function() self:_on_combat_timer() end)
end

function TrainingDummyComponent:_on_health_changed(e)
	local percentage = radiant.entities.get_health_percentage(self._entity)

	if percentage >= 1 then
		self:_enable()
	elseif percentage < self._sv.disable_health_percentage then
		self:_disable()
	end
end

return TrainingDummyComponent