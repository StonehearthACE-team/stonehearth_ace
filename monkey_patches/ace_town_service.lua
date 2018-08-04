local TownService = require 'stonehearth.services.server.town.town_service'
local AceTownService = class()

function AceTownService:calculate_growth_period(player_id, original_growth_period)
	local growth_period = original_growth_period
	local town = self:get_town(player_id)
	if town then
		-- Apply vitality bonus - this is the only part that's actually town-dependent
		local vitality_bonus = town:get_town_bonus('stonehearth:town_bonus:vitality')
		if vitality_bonus then
			growth_period = vitality_bonus:apply_growth_period_bonus(growth_period)
		end
	end

	-- Apply biome growth multiplier
	local biome = stonehearth.world_generation:get_biome()
	if biome and biome.growth_duration_multiplier then
		growth_period = growth_period * biome.growth_duration_multiplier
	end

	-- Apply weather multiplier
	local weather = stonehearth.weather:get_current_weather()
	if weather and weather._sv.plant_growth_time_multiplier then
		growth_period = growth_period * weather._sv.plant_growth_time_multiplier
	end

	if growth_period > 0 then
		return growth_period
	else
		-- Shouldn't happen, but observed in the wild, so be robust.
		return original_growth_period
	end
end

function AceTownService:get_water_affinity_table(climate)
	if not climate then
		climate = 'temperate'	-- change this to read in the current biome's climate once we add climate to them
	end

	local affinity_table = {}
	local climate_data = stonehearth.constants.climates[climate]
	if climate_data then
		local affinity = climate_data.plant_water_affinity or 'MEDIUM'
		affinity_table = stonehearth.constants.plant_water_affinity[affinity] or {}
	end

	return affinity_table
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceTownService:get_best_water_level_from_climate(climate)
	local water_affinity = self:get_water_affinity_table(climate)
	return self:get_best_water_level(water_affinity)
end

function AceTownService:get_best_water_level(water_affinity)
	if not next(water_affinity) then
		return nil
	end

	local best_affinity = water_affinity[1]
	local next_affinity = water_affinity[2]
	for i = 2, water_affinity.n do
		local affinity = water_affinity[i]
		if water_level >= affinity.min_water and affinity.min_water > best_affinity.min_water then
			best_affinity = affinity
			next_affinity = water_affinity[i + 1]
		end
	end

	return best_affinity, next_affinity
end

return AceTownService
