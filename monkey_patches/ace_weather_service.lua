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
         local season = stonehearth.seasons:get_season_for_day(day_since_epoch + i)
         table.insert(self._sv.next_weather_types, self:_get_weather_for_season(season, true))
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

function AceWeatherService:_get_weather_for_season(season, avoid_bad_weather)
   local weighted_set = WeightedSet(rng)
   for _, entry in ipairs(season.weather) do
      -- check if this weather is bad if we want to avoid it
      if avoid_bad_weather then
         local weather = radiant.resources.load_json(entry.uri)
         if not weather.is_bad_weather then
            weighted_set:add(entry.uri, entry.weight)
         end
      else
         weighted_set:add(entry.uri, entry.weight)
      end
   end

   -- if all the weather is bad, just add it all
   if avoid_bad_weather and weighted_set:is_empty() then
      for _, entry in ipairs(season.weather) do
         weighted_set:add(entry.uri, entry.weight)
      end
   end

   return weighted_set:choose_random()
end

return AceWeatherService