local ConsumptionComponent = require 'stonehearth.components.consumption.consumption_component'

local AceConsumptionComponent = class()

AceConsumptionComponent._ace_old_activate = ConsumptionComponent.activate
function AceConsumptionComponent:activate()   
   if not self._sv._food_intolerances then
      self._sv._food_intolerances = ''
   end

   self:_ace_old_activate()  
end

AceConsumptionComponent._ace_old_set_food_preferences = ConsumptionComponent.set_food_preferences
function AceConsumptionComponent:set_food_preferences(preferences, effect)
   self._sv._preference_effect = effect
   self:_ace_old_set_food_preferences(preferences)  
end

function AceConsumptionComponent:set_food_intolerances(intolerances, effect)
   self._sv._food_intolerances = intolerances
   self._sv._intolerance_effect = effect
end

AceConsumptionComponent._ace_old__should_add_food_thought = ConsumptionComponent._should_add_food_thought
function AceConsumptionComponent:_should_add_food_thought(food_quality, now)
   if food_quality <= stonehearth.constants.food_qualities.UNPALATABLE then
      return true
   else
      return self:_ace_old__should_add_food_thought(food_quality, now)
   end
end

function AceConsumptionComponent:_get_quality(food)
   local food_data = radiant.entities.get_entity_data(food, 'stonehearth:food', false)

   if not food_data then
      radiant.assert(false, 'Trying to eat a piece of food that has no entity data.')
      return -1
   end

   if self:_has_food_preferences() and self._sv._preference_effect then
      if radiant.entities.is_material(food, self._sv._food_preferences) then
			radiant.entities.add_buff(self._entity, self._sv._preference_effect)
			return stonehearth.constants.food_qualities.LOVELY
      end
   end
   
   if self:_has_food_intolerances() then
      if radiant.entities.is_material(food, self._sv._food_intolerances) then
			if self._sv._intolerance_effect then
				radiant.entities.add_buff(self._entity, self._sv._intolerance_effect)
				return stonehearth.constants.food_qualities.INTOLERABLE	 
			else
				return stonehearth.constants.food_qualities.UNPALATABLE	
			end
      end
   end
	
	if food_data.applied_buffs then
		for _, applied_buff in ipairs(food_data.applied_buffs) do
			radiant.entities.add_buff(self._entity, applied_buff)
		end
	end
	
   if not food_data.quality then
      log:error('Food %s has no quality entry, defaulting quality to raw & bland.', food)
   end

   return food_data.quality or stonehearth.constants.food_qualities.RAW_BLAND
end

function ConsumptionComponent:_has_food_intolerances()
   return self._sv._food_intolerances ~= ''
end

return AceConsumptionComponent