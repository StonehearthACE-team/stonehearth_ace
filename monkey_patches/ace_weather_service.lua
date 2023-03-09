local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local rng = _radiant.math.get_default_rng()

local AceWeatherService = class()

local NUM_DAYS_TO_PLAN_AHEAD = 3

-- override this function to disallow weather with debuffs for initial selection
function AceWeatherService:_initialize()
   -- Generate weather types if we haven't already.
   if not next(self._sv.next_weather_types) then
      local day_since_epoch = stonehearth.calendar:get_day_since_epoch()
      for i = 0, NUM_DAYS_TO_PLAN_AHEAD - 1 do
         local season, completion = stonehearth.seasons:get_season_for_day(day_since_epoch + i)
         table.insert(self._sv.next_weather_types, self:_get_weather_for_season(season, completion, true))
      end
   end
   
   -- If we have no weather, try switching to one of the ones we just loaded.
   if not self._sv.current_weather_state then
      -- Make sure citizens are created/loaded by the time this runs.
      radiant.on_game_loop_once('set initial weather', function()
            self:_switch_weather()
         end)
   end
end

function AceWeatherService:_switch_weather(instigating_player_id)
   self:_switch_to(self._sv.next_weather_types[1], instigating_player_id)

   -- Consume the oldest weather choice and generate a new weather choice at the end.
   -- worst queue pop ever.
   local new_weather_types = {}
   for i, v in ipairs(self._sv.next_weather_types) do
      if i > 1 then
         table.insert(new_weather_types, v)
      end
   end
   
   local day_since_epoch = stonehearth.calendar:get_day_since_epoch()
   local season, completion = stonehearth.seasons:get_season_for_day(day_since_epoch + NUM_DAYS_TO_PLAN_AHEAD - 1)

   local newly_selected_weather_type = self._sv.weather_override or self:_get_weather_for_season(season, completion)
   table.insert(new_weather_types, newly_selected_weather_type)
   self._sv.next_weather_types = new_weather_types
   self.__saved_variables:mark_changed()
end

function AceWeatherService:_switch_to(weather_uri, instigating_player_id, is_dynamic_switch)
   if self._sv.current_weather_state then
      self._sv.current_weather_state:stop()
   end
   if self._sv.last_weather_state then
      self._sv.last_weather_state:destroy()
   end
   self._sv.last_weather_state = self._sv.current_weather_state
   self._sv.current_weather_state = nil

   self._sv.current_weather_state = radiant.create_controller('stonehearth:weather_state', weather_uri)
   self._sv.current_weather_state:start(instigating_player_id, is_dynamic_switch)
   
   self._sv.current_weather_stamp = self._sv.current_weather_stamp + 1

   self.__saved_variables:mark_changed()
end

function AceWeatherService:set_weather_override(weather_uri, instigating_player_id)  -- nil clears override
   self._sv.weather_override = weather_uri
   self._sv.next_weather_types = {}
   local day_since_epoch = stonehearth.calendar:get_day_since_epoch()
   for i = 0, NUM_DAYS_TO_PLAN_AHEAD - 1 do
      local season, completion = stonehearth.seasons:get_season_for_day(day_since_epoch + i)
      table.insert(self._sv.next_weather_types, self._sv.weather_override or self:_get_weather_for_season(season, completion))
   end
   self:_switch_weather(instigating_player_id)
end

function AceWeatherService:_get_weather_for_season(season, completion, avoid_bad_weather)
   local weighted_set = WeightedSet(rng)
	local current_stage = nil
   for _, entry in ipairs(season.weather) do
		current_stage = nil
		if radiant.util.is_table(entry.weight) and completion then
			-- check which stage of the season we are if multiple season stages are present
			current_stage = 1 + math.floor(completion / (1 / radiant.size(entry.weight)))
		end
		-- check if this weather is bad if we want to avoid it
		if avoid_bad_weather then
			local weather = radiant.resources.load_json(entry.uri)
			if not weather.is_bad_weather then
				if current_stage then
					weighted_set:add(entry.uri, entry.weight[current_stage]) -- if season stages are present
				else
					weighted_set:add(entry.uri, entry.weight)
				end
			end
		else
			if current_stage then
				weighted_set:add(entry.uri, entry.weight[current_stage]) -- if season stages are present
			else
				weighted_set:add(entry.uri, entry.weight)
			end
		end
   end

   -- if all the weather is bad, just add it all
   if avoid_bad_weather and weighted_set:is_empty() then
      for _, entry in ipairs(season.weather) do
			if current_stage then
				weighted_set:add(entry.uri, entry.weight[current_stage]) -- if season stages are present
			else
				weighted_set:add(entry.uri, entry.weight)
			end
      end
   end

   return weighted_set:choose_random()
end

function AceWeatherService:is_cold_weather()
   local state = self._sv.current_weather_state
   return state and state:is_cold_weather()
end

function AceWeatherService:is_warm_weather()
   local state = self._sv.current_weather_state
   return state and state:is_warm_weather()
end

function AceWeatherService:is_bad_weather()
   local state = self._sv.current_weather_state
   return state and state:is_bad_weather()
end

function AceWeatherService:is_frozen()
   local state = self._sv.current_weather_state
   return state and state:is_frozen()
end

function AceWeatherService:get_weather_type(weather)
   local json = weather and weather:get_json()
   if json then
      for weather_type, property in pairs(stonehearth.constants.weather.weather_types) do
         if json[property] then
            return weather_type
         end
      end
   end
end

function AceWeatherService:get_current_weather_type()
   local weather = self:get_current_weather()
   return self:get_weather_type(weather)
end

return AceWeatherService