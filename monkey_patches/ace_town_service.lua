local TownService = require 'stonehearth.services.server.town.town_service'
local AceTownService = class()

local _water_affinities = {}
local _light_affinities = {}

function AceTownService:calculate_growth_period(player_id, original_growth_period)
	local growth_period = self:calculate_town_bonuses_growth_period(player_id, original_growth_period)

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

function AceTownService:calculate_town_bonuses_growth_period(player_id, original_growth_period)
   local growth_period = original_growth_period
	local town = self:get_town(player_id)
	if town then
      -- Apply vitality bonus - this is the only part that's actually town-dependent
      -- switched to doing this generically so any bonus that has an `apply_growth_period_bonus` function will have that called
      for _, town_bonus in pairs(town:get_active_town_bonuses()) do
         if town_bonus.apply_growth_period_bonus then
            growth_period = town_bonus:apply_growth_period_bonus(growth_period)
         end
      end
      
      if growth_period <= 0 then
         growth_period = original_growth_period
      end
   end

   return growth_period
end

function AceTownService:get_water_affinity_table(climate)
	if not climate then
		climate = self:_get_default_climate()
   end
   
   local affinity_table = _water_affinities[climate]
   if not affinity_table then
      affinity_table = {}
      local climate_data = stonehearth.constants.climates[climate]
      if climate_data then
         local affinity = climate_data.plant_water_affinity or 'MEDIUM'
         affinity_table = stonehearth.constants.plant_water_affinity[affinity] or {}
      end
      _water_affinities[climate] = affinity_table
   end

	return affinity_table
end

function AceTownService:get_light_affinity_table(climate)
	if not climate then
		climate = self:_get_default_climate()
	end

   local affinity_table = _light_affinities[climate]
   if not affinity_table then
      affinity_table = {}
      local climate_data = stonehearth.constants.climates[climate]
      if climate_data then
         local affinity = climate_data.plant_light_affinity or 'MEDIUM'
         affinity_table = stonehearth.constants.plant_light_affinity[affinity] or {}
      end
      _light_affinities[climate] = affinity_table
   end

	return affinity_table
end

function AceTownService:_get_default_climate()
   if not self._default_climate then
      local biome_uri = stonehearth.world_generation:get_biome_alias()
      local biome = biome_uri and radiant.resources.load_json(biome_uri)
      if biome then
         self._default_climate = biome.climate or 'temperate_medium'
      else
         return 'temperate_medium'
      end
   end
   return self._default_climate
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceTownService:get_best_water_level_from_climate(climate)
	local water_affinity = self:get_water_affinity_table(climate)
	return self:get_best_affinity_level(water_affinity)
end

function AceTownService:get_best_light_level_from_climate(climate)
	local light_affinity = self:get_light_affinity_table(climate)
	return self:get_best_affinity_level(light_affinity)
end

function AceTownService:get_best_affinity_level(affinities)
	if not next(affinities) then
		return nil
	end

	local best_affinity = affinities[1]
	local next_affinity = affinities[2]
	for i = 2, #affinities do
		local affinity = affinities[i]
		if affinity.period_multiplier < best_affinity.period_multiplier then
			best_affinity = affinity
			next_affinity = affinities[i + 1]
		end
	end

	return best_affinity, next_affinity
end

function AceTownService:_get_modifier_from_level(affinity, level)
   local best_affinity = {min_level = -1, period_multiplier = 1}
	for _, affinity in ipairs(affinity) do
		if level >= affinity.min_level and affinity.min_level > best_affinity.min_level then
			best_affinity = affinity
		end
   end
   return best_affinity.period_multiplier
end

function AceTownService:get_environmental_growth_time_modifier(climate, humidity, light, flood_multiplier, frozen_multiplier)
   local modifier = (flood_multiplier or 1) * (frozen_multiplier or 1)

   modifier = modifier * self:_get_modifier_from_level(self:get_water_affinity_table(climate), humidity)
   modifier = modifier * self:_get_modifier_from_level(self:get_light_affinity_table(climate), light)

   return modifier
end

-- go through each town and check if it's tier 3
-- if so, collect important data from it
function AceTownService:get_persistence_data()
   local data = {}
   for player_id, town in pairs(self._sv.towns) do
      local pop = stonehearth.population:get_population(player_id)
      if pop and not pop:is_npc() and pop:get_city_tier() >= 3 then
         data[player_id] = town:get_persistence_data()
      end
   end
   return data
end

-- attempted fix to rare issue of red_alert.js calling it before player has been fully set up?
function AceTownService:town_alert_enabled_command(session, response)
   local town = self:get_town(session.player_id)
   local enabled = town and town:town_alert_enabled()
   return { enabled = enabled }
end

return AceTownService
