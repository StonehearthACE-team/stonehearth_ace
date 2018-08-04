local EvolveComponent = require 'stonehearth.components.evolve.evolve_component'
local AceEvolveComponent = class()

AceEvolveComponent._old_initialize = EvolveComponent.initialize
function AceEvolveComponent:initialize()
	self:_old_initialize()

	self._sv.local_water_modifier = 1
	-- would need to set up a child entity with its own water component for detecting flooding in a smaller region
	--self._sv.is_flooded = false
	self._sv.current_growth_recalculate_progress = 0
	self.__saved_variables:mark_changed()
end

AceEvolveComponent._old_activate = EvolveComponent.activate
function AceEvolveComponent:activate()
	self:_old_activate()

	-- we don't care about water for animals, only for plants
	local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
	if catalog_data.category == 'seed' or catalog_data.category == 'plants' then
		local json = radiant.entities.get_json(self)
		self._preferred_climate = json and json.preferred_climate
		self._water_affinity = stonehearth.town:get_water_affinity_table(self._preferred_climate)
		--self._flood_period_multiplier = (json and json.flood_period_multiplier) or 2
		-- determine the "reach" of water detection from json; otherwise just expand 1 outwards and downwards from destination region
		self._water_reach = (json and json.water_reach) or 1

		self:_create_water_listener()
	end
end

AceEvolveComponent._old_destroy = EvolveComponent.destroy
function AceEvolveComponent:destroy()
   self:_old_destroy()

   self:_destroy_water_listener()
end

function AceEvolveComponent:_create_water_listener()
	if self._water_listener then
		self:_destroy_water_listener()
	end

	local reach = self._water_reach
	local region = self._entity:get_component('destination') or self._entity:get_component('region_collision_shape')
	-- if there's no destination or collision region, oh well, guess we're not creating a listener
	if not region then
		return
	end

	self._water_region = region:get_region():get()
						:extruded('x', reach, reach)
						:extruded('z', reach, reach)
						:extruded('y', reach, 0)
	local water_component = self._entity:add_component('stonehearth_ace:water_signal')
	water_component:set_region(self._water_region)
	self._water_listener = radiant.events.listen(self._entity, 'stonehearth_ace:water_signal:water_volume_changed', self, self._on_water_volume_changed)
end

function AceEvolveComponent:_destroy_water_listener()
	if self._water_listener then
		self._water_listener:destroy()
		self._water_listener = nil
	end
end

function AceEvolveComponent:_on_water_volume_changed(volume)
	-- water level is a ratio of volume to "normal ideal volume for this plant"
	-- we consider the normal ideal ratio for a plant to be 1 water per square root of its detection area
	local area = self._water_region:get_area()
	--local ideal_ratio = 1 / math.sqrt(area)
	--local this_ratio = volume / area
	--self._sv._water_level = this_ratio / ideal_ratio
	-- the above simplifies to this:
	self._sv._water_level = volume / math.sqrt(area)
	
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
	end

	self.__saved_variables:mark_changed()
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceEvolveComponent:get_best_water_level()
	if not next(self._water_affinity) then
		return nil
	end

	local best_affinity = self._water_affinity[1]
	local next_affinity = self._water_affinity[2]
	for i = 2, self._water_affinity.n do
		local affinity = self._water_affinity[i]
		if water_level >= affinity.min_water and affinity.min_water > best_affinity.min_water then
			best_affinity = affinity
			next_affinity = self._water_affinity[i + 1]
		end
	end

	return best_affinity, next_affinity
end

function AceEvolveComponent:_start_evolve_timer()
	self:_stop_evolve_timer()
   
	local duration = self:_calculate_growth_period()
	self._sv.evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", duration, radiant.bind(self, 'evolve'))

	self.__saved_variables:mark_changed()
end

function AceEvolveComponent:_recalculate_duration()
	if self._sv.evolve_timer then
		local old_duration = self._sv.evolve_timer:get_duration()
		local old_expire_time = self._sv.evolve_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration
		local evolve_period = self:_get_base_growth_period()
		
		local old_progress = self:_get_current_growth_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv.current_growth_recalculate_progress = old_progress + new_progress
		local time_remaining = math.max(0, evolve_period * (1 - self._sv.current_growth_recalculate_progress))
		if time_remaining > 0 then
			local scaled_time_remaining = self:_calculate_growth_period(time_remaining)
			self._sv.evolve_timer:destroy()
			self._sv.evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", scaled_time_remaining, radiant.bind(self, 'evolve'))
		else
			self:evolve()
		end
	end
end

function AceEvolveComponent:_get_current_growth_recalculate_progress()
	return self._sv.current_growth_recalculate_progress or 0
end

function AceEvolveComponent:_get_base_growth_period()
	local growth_period = stonehearth.calendar:parse_duration(self._evolve_data.evolve_time)
	--if self._is_in_preferred_season == false then  -- Nil is equivalent to preferred.
	--	growth_period = growth_period * stonehearth.constants.farming.NONPREFERRED_SEASON_GROWTH_TIME_MULTIPLIER
	--end
	return growth_period
end

function AceEvolveComponent:_calculate_growth_period(evolve_time)
	if not evolve_time then
		evolve_time = self:_get_base_growth_period()
	end
	
	local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
	if catalog_data.category == 'seed' or catalog_data.category == 'plants' then
		evolve_time = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), evolve_time) * self._sv.local_water_modifier
		--if self._sv.is_flooded then
		--	evolve_time = evolve_time * self._flood_period_multiplier
		--end
	end

	return evolve_time
end

return AceEvolveComponent
