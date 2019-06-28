local FoodPreferenceTrait = require 'stonehearth.data.traits.food_preference.food_preference_script'
local AceFoodPreferenceTrait = class()

local ATE_INTOLERABLE_THOUGHT = 'stonehearth:thoughts:eating:ate_intolerable'
local ATE_LOVELY_THOUGHT = 'stonehearth:thoughts:eating:ate_lovely'

local DRANK_UNPALATABLE_THOUGHT = 'stonehearth:thoughts:drinking:unpalatable'
local DRANK_INTOLERABLE_THOUGHT = 'stonehearth:thoughts:drinking:intolerable'
local DRANK_LOVELY_THOUGHT = 'stonehearth:thoughts:drinking:lovely'

AceFoodPreferenceTrait._ace_old_destroy = FoodPreferenceTrait.destroy
function AceFoodPreferenceTrait:destroy()
   self:_ace_old_destroy()
   
	if self._on_drink_listener then
      self._on_drink_listener:destroy()
      self._on_drink_listener = nil
   end
	
   local consumption = self._sv._entity:get_component('stonehearth:consumption')
   if consumption then
      consumption:set_food_intolerances('')
		
		consumption:set_drink_intolerances('')
   end
   
   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   if thoughts_component then
      thoughts_component:remove_response(self._intolerable_thought_id, ATE_INTOLERABLE_THOUGHT)
      thoughts_component:remove_response(self._lovely_thought_id, ATE_LOVELY_THOUGHT)
		
		thoughts_component:remove_response(self._drink_unpalatable_thought_id, DRANK_UNPALATABLE_THOUGHT)
		thoughts_component:remove_response(self._drink_intolerable_thought_id, DRANK_INTOLERABLE_THOUGHT)
      thoughts_component:remove_response(self._drink_lovely_thought_id, DRANK_LOVELY_THOUGHT)
   end
end

function AceFoodPreferenceTrait:activate()  
   local consumption = self._sv._entity:get_component('stonehearth:consumption')
   if consumption then
      consumption:set_food_intolerances(self._food_intolerances, self._intolerance_effect)
      consumption:set_food_preferences(self._food_preferences, self._preference_effect)
		
		consumption:set_drink_intolerances(self._drink_intolerances, self._drink_intolerance_effect)
      consumption:set_drink_preferences(self._drink_preferences, self._drink_preference_effect)
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
	
   self._drink_preferences = json.data.drink_preferences or ''
	self._drink_preference_effect = json.data.drink_preference_effect
	self._drink_lovely_thought = json.data.drink_lovely_thought or DRANK_LOVELY_THOUGHT
   self._drink_unpalatable_thought = json.data.drink_unpalatable_thought or DRANK_UNPALATABLE_THOUGHT
	self._drink_intolerances = json.data.drink_intolerances or ''
   self._drink_intolerance_effect = json.data.drink_intolerance_effect
	self._drink_intolerable_thought = json.data.drink_unpalatable_thought or DRANK_INTOLERABLE_THOUGHT
end

AceFoodPreferenceTrait._ace_old__map_thoughts = FoodPreferenceTrait._map_thoughts
function AceFoodPreferenceTrait:_map_thoughts()
   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   if self._intolerance_effect then
      self._intolerable_thought_id = thoughts_component:add_thought_response(ATE_INTOLERABLE_THOUGHT, self._intolerable_thought)
   end 
	
	if self._drink_intolerance_effect then
      self._drink_intolerable_thought_id = thoughts_component:add_thought_response(DRANK_INTOLERABLE_THOUGHT, self._drink_intolerable_thought)
   end 
   
   if self._preference_effect then 
      self._lovely_thought_id = thoughts_component:add_thought_response(ATE_LOVELY_THOUGHT, self._lovely_thought)
   end
	
	if self._drink_preference_effect then 
      self._drink_lovely_thought_id = thoughts_component:add_thought_response(DRANK_LOVELY_THOUGHT, self._drink_lovely_thought)
   end
	
	if self._drink_unpalatable_thought then
		self._drink_unpalatable_thought_id = thoughts_component:add_thought_response(DRANK_UNPALATABLE_THOUGHT, self._drink_unpalatable_thought)
	end
   
   self:_ace_old__map_thoughts() 
end

return AceFoodPreferenceTrait
