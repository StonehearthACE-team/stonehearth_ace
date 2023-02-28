local AceSeasonsService = class()

local DEFAULT_WEATHER = 'stonehearth:weather:sunny'
local CALENDAR_CONSTANTS = radiant.resources.load_json('/stonehearth/data/calendar/calendar_constants.json')
local DAYS_PER_YEAR = CALENDAR_CONSTANTS.days_per_month * CALENDAR_CONSTANTS.months_per_year
local SECONDS_PER_DAY = CALENDAR_CONSTANTS.hours_per_day * CALENDAR_CONSTANTS.minutes_per_hour * CALENDAR_CONSTANTS.seconds_per_minute

local terrain_blocks = radiant.resources.load_json("stonehearth:terrain_blocks", true, false)

local log = radiant.log.create_logger('seasons')

-- Also return the season completion on that day
function AceSeasonsService:get_season_for_day(day_since_epoch)
   if not self._seasons then
      return nil  -- Not loaded yet.
   else
      assert(next(self._seasons))
		table.sort(self._seasons, function(a, b)
			return a.start_day < b.start_day
		end)

		for i, season in ipairs(self._seasons) do
			season.end_day = self._seasons[i == #self._seasons and 1 or (i + 1)].start_day
		end
		
		local day_of_year = 1 + day_since_epoch % DAYS_PER_YEAR
		local season = nil
		local current_season = nil
      for i = #self._seasons, 1, -1 do
         season = self._seasons[i]
         if day_of_year >= season.start_day then
				current_season = season
				break
         end
      end
		
		if current_season then
			local duration = current_season.end_day - current_season.start_day
			local day_of_season = math.max(1, (day_of_year - season.start_day))
			local completion = math.max(0, math.min(day_of_season / duration, 1))
			if completion then
				return current_season, completion
			else
				return current_season
			end
		end
      assert(false, 'Could not find season for day ' .. tostring(day_of_year))
   end
end

function AceSeasonsService:_load_season_config(biome_uri)
   self._seasons = self:_get_seasons_data(biome_uri)

   table.sort(self._seasons, function(a, b)
      return a.start_day < b.start_day
   end)

   for i, season in ipairs(self._seasons) do
      season.end_day = self._seasons[i == #self._seasons and 1 or (i + 1)].start_day
   end
   
   self._is_in_transition = true  -- Force an update.
   self:_update_transition()
   radiant.events.listen_once(radiant, 'stonehearth:start_date_set', function(e)
         self._is_in_transition = true  -- Force an update.
         self:_update_transition()
         radiant.events.trigger_async(self, 'stonehearth:seasons:initial_set')
      end)
   
   self:_resolve_get_seasons_commands(self._get_seasons_futures)
   self._get_seasons_futures = {}
      
   radiant.events.trigger_async(radiant, 'stonehearth:seasons_set')
end

function AceSeasonsService:_get_seasons_data(biome_uri)
   local biome = radiant.resources.load_json(biome_uri)
   assert(biome, 'biome not found: ' .. biome_uri)
   local generation_data = radiant.resources.load_json(biome.generation_file)
   assert(generation_data and generation_data.palettes, 'biome generation_data not found in ' .. biome_uri)
   local default_palette = generation_data.season and generation_data.palettes[generation_data.season] or generation_data.palettes[next(generation_data.palettes)]
   
   local seasons = {}

   if biome.seasons then
      for id, season_config in pairs(biome.seasons) do
         assert(season_config.start_day and season_config.start_day >= 0 and season_config.start_day < DAYS_PER_YEAR,
               'Must specify season start day between 0 and ' .. tostring(DAYS_PER_YEAR))
         table.insert(seasons, self:_get_season_data(biome_uri, generation_data.palettes[id] or default_palette, season_config, id))
      end
   elseif biome.weather then
      -- Just weather. Group it into a single season.
      table.insert(seasons, self:_get_season_data(biome_uri, default_palette, { weather = biome.weather }))
   else
      -- Not even weather defined. I guess it's always sunny.
      table.insert(seasons, self:_get_season_data(biome_uri, default_palette, { weather = { { uri = DEFAULT_WEATHER, weight = 1 } } }))
   end

   for _, season in ipairs(seasons) do
      for block, color in pairs(terrain_blocks.default_colors) do
         if not season.terrain_palette[block] then
            season.terrain_palette[block] = color
         end
      end
   end

   return seasons
end

function AceSeasonsService:_get_season_data(biome_uri, palette, config, id)
   return {
      id = id or 'default',
      display_name = config.display_name or '',
      description = config.description or '',
      start_day = config.start_day or 0,
      sunlight = config.sunlight or 1,
      humidity = config.humidity or 0,
      biome = biome_uri,
      weather = config.weather,
      terrain_palette = palette,
      foraging_spot_uri = config.foraging_spot_uri,
   }
end

return AceSeasonsService
