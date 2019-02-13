local GrowingComponent = require 'stonehearth.components.growing.growing_component'
local AceGrowingComponent = class()
local log = radiant.log.create_logger('growing')

AceGrowingComponent._ace_old_activate = GrowingComponent.activate
function AceGrowingComponent:activate()
	local json = radiant.entities.get_json(self)
	self._preferred_climate = json and json.preferred_climate
   self._water_affinity = stonehearth.town:get_water_affinity_table(self._preferred_climate)
   self._light_affinity = stonehearth.town:get_light_affinity_table(self._preferred_climate)
   self._flood_period_multiplier = (json and json.flood_period_multiplier) or 2
   --self._flooded_growth_only = (json and json.flooded_growth_only) or false   -- if true, only grow when flooded; otherwise normal

   if not self._sv.custom_growth_time_multiplier then
      self._sv.custom_growth_time_multiplier = 1
   end

   if not self._sv._local_water_modifier then
      self._sv._local_water_modifier = 1
   end

   if not self._sv._local_light_modifier then
      self._sv._local_light_modifier = 1
   end

   if not self._sv._current_growth_recalculate_progress then
      self._sv._current_growth_recalculate_progress = 0
   end

   if self._sv._is_flooded == nil then
      self._sv._is_flooded = false
   end

	self:_ace_old_activate()
end

function AceGrowingComponent:post_activate()
   self:_create_water_listener()

   -- growth stages are expressed with unit_info display_name, but we want to lock custom_names for these entities
   self._entity:add_component('stonehearth:unit_info'):lock('stonehearth:growing')
end

AceGrowingComponent._ace_old_destroy = GrowingComponent.destroy
function AceGrowingComponent:destroy()
   self:_ace_old_destroy()

   self:_destroy_water_listener()
   if self._sv._is_flooded then
      radiant.events.trigger(self._entity, 'stonehearth_ace:growing:flooded_changed', false)
   end
end

function AceGrowingComponent:_create_water_listener()
   local water_component = self._entity:add_component('stonehearth_ace:water_signal')
   self._water_signal = water_component:set_signal('growing', nil, {'water_exists'}, function(changes) self:_on_water_signal_changed(changes) end)
end

function AceGrowingComponent:_destroy_water_listener()
	if self._flood_listener then
		self._flood_listener:destroy()
		self._flood_listener = nil
	end
end

function AceGrowingComponent:_on_water_signal_changed(changes)
   log:debug('%s _on_water_signal_changed: %s', self._entity, radiant.util.table_tostring(changes))
   
   if changes.water_exists.value ~= self._sv._is_flooded then
      self._sv._is_flooded = changes.water_exists.value
      self:_recalculate_duration()
      radiant.events.trigger(self._entity, 'stonehearth_ace:growing:flooded_changed', self._sv._is_flooded)

      self.__saved_variables:mark_changed()
   end
end

function AceGrowingComponent:set_growth_factors(humidity, sunlight)
	-- water level is a ratio of volume to "normal ideal volume for a full farm plot"
   local changed = false
   local humidity_modifier = self:_get_modifier_from_level(self._water_affinity, humidity)
   local sunlight_modifier = self:_get_modifier_from_level(self._light_affinity, sunlight)

	if humidity_modifier ~= self._sv._local_water_modifier then
      self._sv._local_water_modifier = humidity_modifier
      changed = true
   end

   if sunlight_modifier ~= self._sv._local_light_modifier then
      self._sv._local_light_modifier = sunlight_modifier
      changed = true
   end

   if changed then
		self:_recalculate_duration()
		self.__saved_variables:mark_changed()
   end
end

function AceGrowingComponent:_get_modifier_from_level(affinity, level)
   local best_affinity = {min_level = -1, period_multiplier = 1}
	for _, affinity in ipairs(affinity) do
		if level >= affinity.min_level and affinity.min_level > best_affinity.min_level then
			best_affinity = affinity
		end
   end
   return best_affinity.period_multiplier
end

function AceGrowingComponent:is_flooded()
   return self._sv._is_flooded
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceGrowingComponent:get_best_water_level()
	return stonehearth.town:get_best_affinity_level(self._water_affinity)
end

function AceGrowingComponent:get_best_light_level()
	return stonehearth.town:get_best_affinity_level(self._light_affinity)
end

function AceGrowingComponent:modify_custom_growth_time_multiplier(multiplier)
   if multiplier ~= 1 then
      self:set_custom_growth_time_multiplier(self._sv.custom_growth_time_multiplier * multiplier)
   end
end

function AceGrowingComponent:set_custom_growth_time_multiplier(multiplier)
   if self._sv.custom_growth_time_multiplier ~= multiplier then
      self._sv.custom_growth_time_multiplier = multiplier
      self:_recalculate_duration()
		self.__saved_variables:mark_changed()
   end
end

function AceGrowingComponent:_recalculate_duration()
   if self._sv.growth_timer then
		local old_duration = self._sv.growth_timer:get_duration()
		local old_expire_time = self._sv.growth_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration
		local growth_period = self:_get_base_growth_period()
	  
		local old_progress = self:_get_current_growth_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv._current_growth_recalculate_progress = old_progress + new_progress
		local time_remaining = math.max(0, growth_period * (1 - self._sv._current_growth_recalculate_progress))
		local scaled_time_remaining = self:_calculate_growth_period(time_remaining)
		self._sv.growth_timer:destroy()
		self._sv.growth_timer = stonehearth.calendar:set_persistent_timer("GrowingComponent grow_callback", scaled_time_remaining, radiant.bind(self, '_grow'))
	end
end

function AceGrowingComponent:_get_current_growth_recalculate_progress()
	return self._sv._current_growth_recalculate_progress or 0
end

function AceGrowingComponent:_calculate_growth_period(growth_period)
	if not growth_period then
		growth_period = self:_get_base_growth_period()
   end
   -- we don't want the biome/weather modifiers, those should be handled with sunlight/humidity values
   -- we only care about the vitality town bonus (and any other bonuses that may get modded in)
   local scaled_growth_period = stonehearth.town:calculate_town_bonuses_growth_period(self._entity:get_player_id(), growth_period) * self._sv.custom_growth_time_multiplier
   
   if self._sv._is_flooded then
		scaled_growth_period = scaled_growth_period * self._flood_period_multiplier
   end

   if self._sv._local_water_modifier then
      scaled_growth_period = scaled_growth_period * self._sv._local_water_modifier
   end

   if self._sv._local_light_modifier then
      scaled_growth_period = scaled_growth_period * self._sv._local_light_modifier
   end

	return scaled_growth_period
end

function AceGrowingComponent:_set_growth_timer()
   local growth_period = self:_calculate_growth_period()
   if self._sv.growth_timer then
      self._sv.growth_timer:destroy()
      self._sv.growth_timer = nil
   end
   self._sv.growth_timer = stonehearth.calendar:set_persistent_timer("GrowingComponent grow_callback", growth_period, radiant.bind(self, '_grow'))
end

AceGrowingComponent._ace_old__grow = GrowingComponent._grow
function AceGrowingComponent:_grow()
	self:_ace_old__grow()

	self._sv._current_growth_recalculate_progress = 0
end

return AceGrowingComponent
