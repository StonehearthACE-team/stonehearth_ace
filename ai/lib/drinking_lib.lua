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

function DrinkingLib.get_quality(drink_stuff, drink_preferences, drink_intolerances, hour_type, weather_type)
   local drink = drink_stuff
   local container_data = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink_container', false)
   if container_data then
      drink = container_data.drink
   end
   local drink_data = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink', false)

   if not drink_data or not drink_data.default then
      return nil
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

   local quality = drink_data.quality or qualities.RAW_BLAND
   local weather_types = stonehearth.constants.weather.weather_types
	
	if weather_type == weather_types.COLD then
		if radiant.entities.is_material(drink_stuff, 'warming') then
         quality = quality + 3
		elseif radiant.entities.is_material(drink_stuff, 'refreshing') then
			quality = quality - 2
		end
	elseif weather_type == weather_types.HOT then
		if radiant.entities.is_material(drink_stuff, 'refreshing') then
         quality = quality + 3
		elseif radiant.entities.is_material(drink_stuff, 'warming') then
			quality = quality - 2
		end
	end

   local times = stonehearth.constants.drink_satiety
	
   if hour_type == times.DRINKTIME_NIGHT_START then
      if not radiant.entities.is_material(drink_stuff, 'night_time') then
         quality = quality - 2
      end
	elseif hour_type == times.DRINKTIME_AFTERNOON_START then
		if radiant.entities.is_material(drink_stuff, 'night_time') then
         quality = quality - 2
		elseif not radiant.entities.is_material(drink_stuff, 'afternoon_time') then
         quality = quality - 3
		elseif radiant.entities.is_material(drink_stuff, 'afternoon_time') then
			quality = quality + 2
      end
	else  --if hour_type == times.DRINKTIME_MORNING_START then
		if radiant.entities.is_material(drink_stuff, 'night_time') then
         quality = quality - 6
		elseif not radiant.entities.is_material(drink_stuff, 'morning_time') then
         quality = quality - 1
      elseif radiant.entities.is_material(drink_stuff, 'morning_time')then
			quality = quality + 2
		end
	end

   return math.max(quality, qualities.UNPALATABLE)
end

function DrinkingLib.make_drink_filter(drink_preferences, drink_intolerances, hour_type, weather_type)
   return stonehearth.ai:filter_from_key('drink_filter', tostring(drink_preferences, drink_intolerances, hour_type, weather_type), function(item)
            local quality = DrinkingLib.get_quality(item, drink_preferences, drink_intolerances, hour_type, weather_type)
            return quality and quality >= stonehearth.constants.drink_qualities.MINIMUM_VIABLE
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