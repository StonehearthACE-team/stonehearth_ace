local DrinkingLib = class()
local log = radiant.log.create_logger('drinking_lib')

local get_modified_drink_quality = function(quality, addend, default)
   return quality and (quality + addend) or default
end

function DrinkingLib.get_quality(drink_stuff, drink_preferences, drink_intolerances)
	local now = stonehearth.calendar:get_time_and_date()
	local weather = stonehearth.weather:get_current_weather():get_uri()
   local drink = drink_stuff
   local container_data = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink_container', false)
   if container_data then
      drink = container_data.drink
   end
   local drink_data = radiant.entities.get_entity_data(drink, 'stonehearth_ace:drink', false)

   if not drink_data or not drink_data.default then
      return nil
   end

	if drink_intolerances ~= '' then
      if radiant.entities.is_material(drink_stuff, drink_intolerances) then
         return stonehearth.constants.drink_qualities.INTOLERABLE
      end
   end
	
   if drink_preferences ~= '' then
      if not radiant.entities.is_material(drink_stuff, drink_preferences) then
         return stonehearth.constants.drink_qualities.UNPALATABLE
      end
   end
	
	if stonehearth.constants.weather.cold_weathers[weather] then
		if radiant.entities.is_material(drink_stuff, 'warming') then
         return get_modified_drink_quality(drink_data.quality, 3, stonehearth.constants.drink_qualities.PREPARED_AVERAGE)
		elseif radiant.entities.is_material(drink_stuff, 'refreshing') then
			return get_modified_drink_quality(drink_data.quality, -2, stonehearth.constants.drink_qualities.RAW_AVERAGE)
		end
	end
	
	if stonehearth.constants.weather.hot_weathers[weather] then
		if radiant.entities.is_material(drink_stuff, 'refreshing') then
         return get_modified_drink_quality(drink_data.quality, 3, stonehearth.constants.drink_qualities.PREPARED_AVERAGE)
		elseif radiant.entities.is_material(drink_stuff, 'warming') then
			return get_modified_drink_quality(drink_data.quality, -2, stonehearth.constants.drink_qualities.RAW_AVERAGE)
		end
	end
	
	if now.hour >= stonehearth.constants.drink_satiety.DRINKTIME_NIGHT_START and not radiant.entities.is_material(drink_stuff, 'night_time') then
      return get_modified_drink_quality(drink_data.quality, -2, stonehearth.constants.drink_qualities.RAW_BLAND)
	end 
	
	if now.hour >= stonehearth.constants.drink_satiety.DRINKTIME_AFTERNOON_START then
		if radiant.entities.is_material(drink_stuff, 'night_time') then
         return get_modified_drink_quality(drink_data.quality, -2, stonehearth.constants.drink_qualities.RAW_BLAND)
		elseif not radiant.entities.is_material(drink_stuff, 'afternoon_time') then
         return get_modified_drink_quality(drink_data.quality, -3, stonehearth.constants.drink_qualities.RAW_BLAND)
		elseif radiant.entities.is_material(drink_stuff, 'afternoon_time') then
			return get_modified_drink_quality(drink_data.quality, 2, stonehearth.constants.drink_qualities.RAW_TASTY)
      end
	end
	
	if now.hour >= stonehearth.constants.drink_satiety.DRINKTIME_MORNING_START then
		if radiant.entities.is_material(drink_stuff, 'night_time') then
         return get_modified_drink_quality(drink_data.quality, -6, stonehearth.constants.drink_qualities.RAW_BLAND)
		elseif not radiant.entities.is_material(drink_stuff, 'morning_time') then
         return get_modified_drink_quality(drink_data.quality, -1, stonehearth.constants.drink_qualities.RAW_BLAND)
      elseif radiant.entities.is_material(drink_stuff, 'morning_time')then
			return get_modified_drink_quality(drink_data.quality, 2, stonehearth.constants.drink_qualities.RAW_TASTY)
		end
	end

   return drink_data.quality or stonehearth.constants.drink_qualities.RAW_BLAND
end

function DrinkingLib.make_drink_filter(drink_preferences, drink_intolerances)
   return stonehearth.ai:filter_from_key('drink_filter', tostring(drink_preferences, drink_intolerances), function(item)
            return DrinkingLib.get_quality(item, drink_preferences, drink_intolerances) ~= nil
         end)
end

function DrinkingLib.make_drink_rater(drink_preferences, drink_intolerances)
   return function(item)
      local quality = DrinkingLib.get_quality(item, drink_preferences, drink_intolerances)
      if not quality then
         log:error('nil drink quality %s: %s, %s', tostring(item), tostring(drink_preferences), tostring(drink_intolerances))
         return 0
      else
         return (quality - stonehearth.constants.drink_qualities.MINIMUM_VIABLE)
               / (stonehearth.constants.drink_qualities.MAXIMUM - stonehearth.constants.drink_qualities.MINIMUM_VIABLE)
      end
   end
end

return DrinkingLib