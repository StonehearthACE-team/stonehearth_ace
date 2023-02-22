local EatingLib = require 'stonehearth.ai.lib.eating_lib'
local AceEatingLib = class()

local log = radiant.log.create_logger('eating_lib')

function AceEatingLib.get_current_hour_type()
   local hour = stonehearth.calendar:get_time_and_date().hour
   return AceEatingLib.get_hour_type(hour)
end

function AceEatingLib.get_hour_type(hour)
   local times = stonehearth.constants.food
   if hour >= times.MEALTIME_DINNER_START or hour < times.MEALTIME_BREAKFAST_START then
      return times.MEALTIME_DINNER_START
   elseif hour >= times.MEALTIME_START then
      return times.MEALTIME_START
   else  --if hour >= times.MEALTIME_BREAKFAST_START then
      return times.MEALTIME_BREAKFAST_START
   end
end

function AceEatingLib.is_edible(food_stuff)
   local container_data = radiant.entities.get_entity_data(food_stuff, 'stonehearth:food_container', false)
   if not container_data then
      -- actually, we don't care about food that isn't in a container
      return false
   end

   local food = container_data.food

   if not stonehearth.catalog:is_material(food, 'food') then
      --log:error('%s food from container %s isn\'t real food!', tostring(food), food_stuff)
      return false
   end

   local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

   if not food_data or not food_data.default then
      return false
   end

   return true
end

function AceEatingLib.get_quality(food_stuff, food_preferences, food_intolerances, hour_type, weather_type)
   local container_data = radiant.entities.get_entity_data(food_stuff, 'stonehearth:food_container', false)
   if not container_data then
      -- actually, we don't care about food that isn't in a container
      return nil
   end

   local food = container_data.food

   if not stonehearth.catalog:is_material(food, 'food') then
      return nil
   end

   local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

   if not food_data or not food_data.default then
      return nil
   end

   local qualities = stonehearth.constants.food_qualities

	if food_intolerances and food_intolerances ~= '' then
      if radiant.entities.is_material(food_stuff, food_intolerances) then
         return qualities.INTOLERABLE
      end
   end

   local quality = food_data.quality or stonehearth.constants.food_qualities.RAW_BLAND
	
   if food_preferences and food_preferences ~= '' then
      if radiant.entities.is_material(food_stuff, food_preferences) then
         return quality * stonehearth.constants.food.PREFERRED_FOOD_BONUS
      end
   end

   local weather_types = stonehearth.constants.weather.weather_types
	
	if weather_type == weather_types.COLD then
		if radiant.entities.is_material(food_stuff, 'warming') then
         quality = quality + 4
		elseif radiant.entities.is_material(food_stuff, 'refreshing') then
			quality = quality - 1
		end
	elseif weather_type == weather_types.HOT then
		if radiant.entities.is_material(food_stuff, 'refreshing') then
         quality = quality + 4
		elseif radiant.entities.is_material(food_stuff, 'warming') then
			quality = quality - 1
		end
   end
   
   local times = stonehearth.constants.food
   
   if hour_type == times.MEALTIME_DINNER_START then
      if not radiant.entities.is_material(food_stuff, 'night_time') then
         quality = quality - 2
      end
   elseif hour_type == times.MEALTIME_START then
		if radiant.entities.is_material(food_stuff, 'dinner_time') then
         quality = quality - 1
		elseif not radiant.entities.is_material(food_stuff, 'lunch_time') then
         quality = quality - 2
		elseif radiant.entities.is_material(food_stuff, 'lunch_time') then
			quality = quality + 1
      end
	elseif hour_type == times.MEALTIME_BREAKFAST_START then
		if radiant.entities.is_material(food_stuff, 'dinner_time') then
         quality = quality - 1
		elseif not radiant.entities.is_material(food_stuff, 'breakfast_time') then
         quality = quality - 2
      elseif radiant.entities.is_material(food_stuff, 'breakfast_time')then
			quality = quality + 3
		end
	end

   return math.max(quality, qualities.UNPALATABLE)
end

function AceEatingLib.make_food_filter()
   local filter_fn = stonehearth.ai:filter_from_key('food_filter', 'any food! it\'s actually all the same filter!', function(item)
            return AceEatingLib.is_edible(item)
         end)
   -- log:debug('made eating filter_fn for %s: %s', key, tostring(filter_fn))
   -- if not stonehearth_ace.eating_filter_fn then
   --    stonehearth_ace.eating_filter_fn = {}
   -- end
   -- stonehearth_ace.eating_filter_fn[key] = filter_fn
   return filter_fn
end

function AceEatingLib.make_food_rater(food_preferences, food_intolerances, hour_type, weather_type)
   local min = stonehearth.constants.food_qualities.MINIMUM_VIABLE
   local range = stonehearth.constants.food_qualities.MAXIMUM - min
   return function(item)
      return (AceEatingLib.get_quality(item, food_preferences, food_intolerances, hour_type, weather_type) - min) / range
   end
end

return AceEatingLib
