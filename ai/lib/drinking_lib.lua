local DrinkingLib = class()
local log = radiant.log.create_logger('drinking_lib')

function DrinkingLib.get_current_hour_type()
   local hour = stonehearth.calendar:get_time_and_date().hour
   return DrinkingLib.get_hour_type(hour)
end

function DrinkingLib.get_hour_type(hour)
   local times = stonehearth.constants.drink_satiety
   if hour >= times.DRINKTIME_NIGHT_START or hour < times.DRINKTIME_MORNING_START then
      return times.DRINKTIME_NIGHT_START
   elseif hour >= times.DRINKTIME_AFTERNOON_START then
      return times.DRINKTIME_AFTERNOON_START
   else  --if hour >= times.DRINKTIME_MORNING_START then
      return times.DRINKTIME_MORNING_START
   end
end

function DrinkingLib.is_drinkable(drink_stuff, drink_intolerances)
   -- we don't care about drink that isn't in a container
   -- properly formatted drink containers with properly formatted drink has that data catalogued
   local catalog_data = stonehearth.catalog:get_catalog_data(drink_stuff:get_uri())
   if not catalog_data or not catalog_data.drink_satisfaction then
      return false
   end

   if drink_intolerances and drink_intolerances ~= '' then
      if radiant.entities.is_material(drink_stuff, drink_intolerances) then
         return false
      end
   end

   return true
end

function DrinkingLib.get_quality(drink_stuff, drink_preferences, drink_intolerances, hour_type, weather_type)
   -- we don't care about drink that isn't in a container
   -- properly formatted drink containers with properly formatted drink has that data catalogued
   local catalog_data = stonehearth.catalog:get_catalog_data(drink_stuff:get_uri())
   if not catalog_data or not catalog_data.drink_satisfaction then
      return false
   end

   local qualities = stonehearth.constants.drink_qualities

	if drink_intolerances ~= '' then
      if radiant.entities.is_material(drink_stuff, drink_intolerances) then
         return qualities.INTOLERABLE
      end
   end
	
   if drink_preferences ~= '' then
      if not radiant.entities.is_material(drink_stuff, drink_preferences) then
         return qualities.UNPALATABLE
      end
   end

   local quality = catalog_data.drink_quality or qualities.RAW_BLAND
   local weather_types = stonehearth.constants.weather.weather_types
   local drink_attributes = catalog_data.drink_attributes
	
	if weather_type == weather_types.COLD then
		if drink_attributes.is_warming then
         quality = quality + 3
		elseif drink_attributes.is_refreshing then
			quality = quality - 2
		end
	elseif weather_type == weather_types.HOT then
		if drink_attributes.is_refreshing then
         quality = quality + 3
		elseif drink_attributes.is_warming then
			quality = quality - 2
		end
	end

   local times = stonehearth.constants.drink_satiety
	
   if hour_type == times.DRINKTIME_NIGHT_START then
      if not drink_attributes.is_night_time then
         quality = quality - 2
      end
	elseif hour_type == times.DRINKTIME_AFTERNOON_START then
		if drink_attributes.is_night_time then
         quality = quality - 2
		elseif not drink_attributes.is_afternoon_time then
         quality = quality - 3
		elseif drink_attributes.is_afternoon_time then
			quality = quality + 2
      end
	else  --if hour_type == times.DRINKTIME_MORNING_START then
		if drink_attributes.is_night_time then
         quality = quality - 6
		elseif not drink_attributes.is_morning_time then
         quality = quality - 1
      elseif drink_attributes.is_morning_time then
			quality = quality + 2
		end
	end

   return math.max(quality, qualities.UNPALATABLE)
end

-- for the filter, we only actually care about intolerances
-- and this is nil if there's a well available, equivalent to no intolerances, because the well water will simply get rated higher
function DrinkingLib.make_drink_filter(drink_intolerances)
   local key = tostring(drink_intolerances or '')
   return stonehearth.ai:filter_from_key('drink_filter', key, function(item)
            return DrinkingLib.is_drinkable(item, drink_intolerances)
         end)
end

function DrinkingLib.make_drink_rater(drink_preferences, drink_intolerances, hour_type, weather_type)
   local min = stonehearth.constants.drink_qualities.MINIMUM_VIABLE
   local range = stonehearth.constants.drink_qualities.MAXIMUM - min
   return function(item)
      local quality = DrinkingLib.get_quality(item, drink_preferences, drink_intolerances, hour_type, weather_type)
      if not quality then
         log:error('nil drink quality %s: %s, %s', tostring(item), tostring(drink_preferences), tostring(drink_intolerances))
         return 0
      else
         return (quality - min) / range
      end
   end
end

return DrinkingLib