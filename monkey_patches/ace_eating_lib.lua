local EatingLib = require 'stonehearth.ai.lib.eating_lib'
local AceEatingLib = class()

function AceEatingLib.get_quality(food_stuff, food_preferences, food_intolerances)
   local food = food_stuff
   local food_uri = food:get_uri()
   local container_data = radiant.entities.get_entity_data(food, 'stonehearth:food_container', false)
   if container_data then
      food = container_data.food
      food_uri = food
   end

   if not stonehearth.catalog:is_material(food, 'food') then
      return nil
   end

   local food_data = radiant.entities.get_entity_data(food_uri, 'stonehearth:food', false)

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
