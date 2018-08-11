local GrowingComponent = require 'stonehearth.components.growing.growing_component'
local AceGrowingComponent = class()
local log = radiant.log.create_logger('growing')

AceGrowingComponent._old_initialize = GrowingComponent.initialize
function AceGrowingComponent:initialize()
	self:_old_initialize()

	self._sv.local_water_modifier = 1
	self._sv.is_flooded = false
	self._sv.current_growth_recalculate_progress = 0
	self.__saved_variables:mark_changed()
end

AceGrowingComponent._old_activate = GrowingComponent.activate
function AceGrowingComponent:activate()
	local json = radiant.entities.get_json(self)
	self._preferred_climate = json and json.preferred_climate
	self._water_affinity = stonehearth.town:get_water_affinity_table(self._preferred_climate)
	self._flood_period_multiplier = (json and json.flood_period_multiplier) or 2

	self:_old_activate()

	self:_create_water_listener()
end

AceGrowingComponent._old_destroy = GrowingComponent.destroy
function AceGrowingComponent:destroy()
	self:_old_destroy()

	self:_destroy_water_listener()
end

function AceGrowingComponent:_create_water_listener()
	self._entity:add_component('stonehearth_ace:water_signal')
	self._flood_listener = radiant.events.listen(self._entity, 'stonehearth_ace:water_signal:water_exists_changed', self, self._on_water_exists_changed)
end

function AceGrowingComponent:_destroy_water_listener()
	if self._flood_listener then
		self._flood_listener:destroy()
		self._flood_listener = nil
	end
end

function AceGrowingComponent:_on_water_exists_changed(exists)
	self._sv.is_flooded = exists
	self:_recalculate_duration()
	self.__saved_variables:mark_changed()
end

function AceGrowingComponent:set_water_level(water_level)
	-- water level is a ratio of volume to "normal ideal volume for a full farm plot"
	local best_affinity = {min_water = -1, period_multiplier = 1}
	for _, affinity in ipairs(self._water_affinity) do
		if water_level >= affinity.min_water and affinity.min_water > best_affinity.min_water then
			best_affinity = affinity
		end
	end

	local multiplier = best_affinity.period_multiplier
	local prev_modifier = self._sv.local_water_modifier
	if multiplier ~= prev_modifier then
		self._sv.local_water_modifier = multiplier
		self:_recalculate_duration()
		self.__saved_variables:mark_changed()
	end
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceGrowingComponent:get_best_water_level()
	return stonehearth.town:get_best_water_level(self._water_affinity)
end

function AceGrowingComponent:_recalculate_duration()
	if self._sv.growth_timer then
		local old_duration = self._sv.growth_timer:get_duration()
		local old_expire_time = self._sv.growth_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration
		local growth_period = self:_get_base_growth_period()
	  
		local old_progress = self:_get_current_growth_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv.current_growth_recalculate_progress = old_progress + new_progress
		local time_remaining = math.max(0, growth_period * (1 - self._sv.current_growth_recalculate_progress))
		local scaled_time_remaining = self:_calculate_growth_period(time_remaining)
		self._sv.growth_timer:destroy()
		self._sv.growth_timer = stonehearth.calendar:set_persistent_timer("GrowingComponent grow_callback", scaled_time_remaining, radiant.bind(self, '_grow'))
	end
end

function AceGrowingComponent:_get_current_growth_recalculate_progress()
	return self._sv.current_growth_recalculate_progress or 0
end

function AceGrowingComponent:_calculate_growth_period(growth_period)
	if not growth_period then
		growth_period = self:_get_base_growth_period()
	end
	local scaled_growth_period = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), growth_period)
	if self._sv.is_flooded then
		scaled_growth_period = scaled_growth_period * self._flood_period_multiplier
	end
	return scaled_growth_period * (self._sv.local_water_modifier or 1)
end

function AceGrowingComponent:_set_growth_timer()
   local growth_period = self:_calculate_growth_period()
   if self._sv.growth_timer then
      self._sv.growth_timer:destroy()
      self._sv.growth_timer = nil
   end
   self._sv.growth_timer = stonehearth.calendar:set_persistent_timer("GrowingComponent grow_callback", growth_period, radiant.bind(self, '_grow'))
end

AceGrowingComponent._old__grow = GrowingComponent._grow
function AceGrowingComponent:_grow()
	self:_old__grow()

	self._sv.current_growth_recalculate_progress = 0
end

return AceGrowingComponent
