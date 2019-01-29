--[[
   call handlers for getting information to the UI about growing/evolve preferences (e.g., water-related)
]]

local GrowingCallHandler = class()

function GrowingCallHandler:get_growth_preferences_command(session, response, uri)
   response:resolve(self:_get_growth_preferences(uri))
end

-- calls this function to actually get the properties for extensibility purposes
function GrowingCallHandler:_get_growth_preferences(uri)
   local crop_data = radiant.entities.get_component_data(uri, 'stonehearth:crop')
   local growing_data = radiant.entities.get_component_data(uri, 'stonehearth:growing')
   local best_affinity, next_affinity = stonehearth.town:get_best_water_level_from_climate(growing_data.preferred_climate)
   local aquatic_data = radiant.entities.get_component_data(uri, 'stonehearth_ace:aquatic_object') or {}

   local props = {}

   -- include the preferred seasons here so that we can get the id (only the display_name is stored in the farmer_field _sv)
   local preferred_seasons
   if growing_data.preferred_seasons then
      local biome_uri = stonehearth.world_generation:get_biome_alias()
      if biome_uri then  -- Hacky protection against races; should never happen in theory.
         local pref_seasons = growing_data.preferred_seasons[biome_uri]
         if pref_seasons then
            preferred_seasons = radiant.values(pref_seasons)
         end
      end
   end
   props.preferred_seasons = preferred_seasons or {}

   local harvest_stage = 1
   for index, stage in ipairs(growing_data.growth_stages) do
      if stage.model_name == crop_data.harvest_threshhold then
         harvest_stage = index
         break
      end
   end
   local total_time = (harvest_stage - 1) * stonehearth.calendar:parse_duration(growing_data.growth_period)
   local total_growth_time = stonehearth.calendar:convert_to_date(total_time)
   
   -- we only want to express the time in terms of days and hours; round up anything below that
   local _time_durations = stonehearth.calendar:get_time_durations()
   if total_growth_time.minute > 0 or total_growth_time.second > 0 then
      total_growth_time.hour = total_growth_time.hour + 1
      total_growth_time = stonehearth.calendar:convert_to_date(total_growth_time.day * _time_durations.day + total_growth_time.hour * _time_durations.hour)
   end
   props.total_growth_time = total_growth_time

   if total_time <= stonehearth.calendar:parse_duration(stonehearth.constants.farming.crop_growth_times.short) then
      props.growth_time = 'short'
   elseif total_time <= stonehearth.calendar:parse_duration(stonehearth.constants.farming.crop_growth_times.fair) then
      props.growth_time = 'fair'
   else
      props.growth_time = 'long'
   end

   props.preferred_climate = growing_data.preferred_climate
   props.flood_period_multiplier = growing_data.flood_period_multiplier or 2
   props.water_affinity = {
      best_affinity = best_affinity,
      next_affinity = next_affinity
   }
   props.require_flooding_to_grow = aquatic_data.require_water_to_grow

   return props
end

return GrowingCallHandler