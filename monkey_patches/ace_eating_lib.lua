local EatingLib = require 'stonehearth.ai.lib.eating_lib'
local AceEatingLib = class()

function AceEatingLib.get_quality(food_stuff, food_preferences)
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
      if radiant.entities.is_material(food_stuff, food_preferences) then
         return food_data.quality * stonehearth.constants.food.PREFERRED_FOOD_BONUS
      end
   end

   return food_data.quality or stonehearth.constants.food_qualities.RAW_BLAND
end

return AceEatingLib
