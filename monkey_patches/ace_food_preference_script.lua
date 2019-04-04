local FoodPreferenceTrait = require 'stonehearth.data.traits.food_preference.food_preference_script'
local AceFoodPreferenceTrait = class()

local ATE_INTOLERABLE_THOUGHT = 'stonehearth:thoughts:eating:ate_intolerable'
local ATE_LOVELY_THOUGHT = 'stonehearth:thoughts:eating:ate_lovely'

AceFoodPreferenceTrait._ace_old_destroy = FoodPreferenceTrait.destroy
function AceFoodPreferenceTrait:destroy()
   self:_ace_old_destroy()
   
   local consumption = self._sv._entity:get_component('stonehearth:consumption')
   if consumption then
      consumption:set_food_intolerances('')
   end
   
   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   if thoughts_component then
      thoughts_component:remove_response(self._intolerable_thought_id, ATE_INTOLERABLE_THOUGHT)
      thoughts_component:remove_response(self._lovely_thought_id, ATE_LOVELY_THOUGHT)
   end
end

function AceFoodPreferenceTrait:activate()  
   local consumption = self._sv._entity:get_component('stonehearth:consumption')
   if consumption then
      consumption:set_food_intolerances(self._food_intolerances, self._intolerance_effect)
      consumption:set_food_preferences(self._food_preferences, self._preference_effect)
   end

   self:_map_thoughts()
end

AceFoodPreferenceTrait._ace_old__load_preferences = FoodPreferenceTrait._load_preferences
function AceFoodPreferenceTrait:_load_preferences()
   self:_ace_old__load_preferences()
   local json = radiant.resources.load_json(self._sv._uri)
   self._food_intolerances = json.data.food_intolerances or ''
   self._intolerance_effect = json.data.intolerance_effect
   self._preference_effect = json.data.preference_effect
   self._intolerable_thought = json.data.unpalatable_thought or ATE_INTOLERABLE_THOUGHT
   self._lovely_thought = json.data.lovely_thought or ATE_LOVELY_THOUGHT
end

AceFoodPreferenceTrait._ace_old__map_thoughts = FoodPreferenceTrait._map_thoughts
function AceFoodPreferenceTrait:_map_thoughts()
   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   if self._intolerance_effect then
      self._intolerable_thought_id = thoughts_component:add_thought_response(ATE_INTOLERABLE_THOUGHT, self._intolerable_thought)
   end 
   
   if self._preference_effect then 
      self._lovely_thought_id = thoughts_component:add_thought_response(ATE_LOVELY_THOUGHT, self._lovely_thought)
   end
   
   self:_ace_old__map_thoughts() 
end

return AceFoodPreferenceTrait
