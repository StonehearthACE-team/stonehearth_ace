local EatingLib = require 'stonehearth.ai.lib.eating_lib'
local AceEatingLib = class()

function AceEatingLib.get_quality(food_stuff, food_preferences, food_intolerances)
	local now = stonehearth.calendar:get_time_and_date()
	local weather = stonehearth.weather:get_current_weather():get_uri()
   local food = food_stuff
   local food_uri = food:get_uri()
   local container_data = radiant.entities.get_entity_data(food, 'stonehearth:food_container', false)
   if container_data then
      food = container_data.food
      food_uri = food
   end

   if not stonehearth.catalog:is_material(food_uri, 'food') then
      return nil
   end

   local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

   if not food_data or not food_data.default then
      return nil
   end

	if food_intolerances ~= '' then
      if radiant.entities.is_material(food_stuff, food_intolerances) then
         return stonehearth.constants.food_qualities.INTOLERABLE
      end
   end
	
   if food_preferences ~= '' then
      if radiant.entities.is_material(food_stuff, food_preferences) then
         return food_data.quality * stonehearth.constants.food.PREFERRED_FOOD_BONUS
      end
   end
	
	if stonehearth.constants.weather.cold_weathers[weather] then
		if radiant.entities.is_material(food_stuff, 'warming') then
         return food_data.quality + 4 or stonehearth.constants.food_qualities.COOKED_AVERAGE
		elseif radiant.entities.is_material(food_stuff, 'refreshing') then
			return food_data.quality - 1 or stonehearth.constants.food_qualities.RAW_AVERAGE
		end
	end
	
	if stonehearth.constants.weather.hot_weathers[weather] then
		if radiant.entities.is_material(food_stuff, 'refreshing') then
         return food_data.quality + 4 or stonehearth.constants.food_qualities.COOKED_AVERAGE
		elseif radiant.entities.is_material(food_stuff, 'warming') then
			return food_data.quality - 1 or stonehearth.constants.food_qualities.RAW_AVERAGE
		end
	end
	
	if now.hour >= stonehearth.constants.food.MEALTIME_DINNER_START and not radiant.entities.is_material(food_stuff, 'night_time') then
      return food_data.quality - 2 or stonehearth.constants.food_qualities.RAW_BLAND
	end 
	
	if now.hour >= stonehearth.constants.food.MEALTIME_START then
		if radiant.entities.is_material(food_stuff, 'dinner_time') then
         return food_data.quality - 1 or stonehearth.constants.food_qualities.RAW_BLAND
		elseif not radiant.entities.is_material(food_stuff, 'lunch_time') then
         return food_data.quality - 2 or stonehearth.constants.food_qualities.RAW_BLAND
		elseif radiant.entities.is_material(food_stuff, 'lunch_time') then
			return food_data.quality + 1 or stonehearth.constants.food_qualities.RAW_TASTY
      end
	end
	
	if now.hour >= stonehearth.constants.food.MEALTIME_BREAKFAST_START then
		if radiant.entities.is_material(food_stuff, 'dinner_time') then
         return food_data.quality - 1 or stonehearth.constants.food_qualities.RAW_BLAND
		elseif not radiant.entities.is_material(food_stuff, 'breakfast_time') then
         return food_data.quality - 2 or stonehearth.constants.food_qualities.RAW_BLAND
      elseif radiant.entities.is_material(food_stuff, 'breakfast_time')then
			return food_data.quality + 3 or stonehearth.constants.food_qualities.RAW_TASTY
		end
	end

   return food_data.quality or stonehearth.constants.food_qualities.RAW_BLAND
end

function AceEatingLib.make_food_filter(food_preferences, food_intolerances)
   return stonehearth.ai:filter_from_key('food_filter', tostring(food_preferences, food_intolerances), function(item)
            return AceEatingLib.get_quality(item, food_preferences, food_intolerances) ~= nil
         end)
end

function AceEatingLib.make_food_rater(food_preferences, food_intolerances)
   return function(item)
      return (AceEatingLib.get_quality(item, food_preferences, food_intolerances) - stonehearth.constants.food_qualities.MINIMUM_VIABLE)
            / (stonehearth.constants.food_qualities.MAXIMUM - stonehearth.constants.food_qualities.MINIMUM_VIABLE)
   end
end

return AceEatingLib
