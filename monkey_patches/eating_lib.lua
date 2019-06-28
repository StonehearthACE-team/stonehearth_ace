local EatingLib = class()

function EatingLib.get_quality(food_stuff, food_preferences)
   local food = food_stuff
   local container_data = radiant.entities.get_entity_data(food, 'stonehearth:food_container', false)
   if container_data then
      food = container_data.food
   end
   local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

   if not food_data or not food_data.default then
      return nil
   end

   if food_preferences ~= '' then
      if not radiant.entities.is_material(food_stuff, food_preferences) then
         return stonehearth.constants.food_qualities.UNPALATABLE
      end
   end

   return food_data.quality or stonehearth.constants.food_qualities.RAW_BLAND
end

function EatingLib.make_food_filter(food_preferences)
   return stonehearth.ai:filter_from_key('food_filter', tostring(food_preferences), function(item)
            return EatingLib.get_quality(item, food_preferences) ~= nil
         end)
end

function EatingLib.make_food_rater(food_preferences)
   return function(item)
      return (EatingLib.get_quality(item, food_preferences) - stonehearth.constants.food_qualities.MINIMUM_VIABLE)
            / (stonehearth.constants.food_qualities.MAXIMUM - stonehearth.constants.food_qualities.MINIMUM_VIABLE)
   end
end

return EatingLib
