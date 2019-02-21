local FoodPreferenceTrait = require 'stonehearth.data.traits.food_preference.food_preference_script'
local AceFoodPreferenceTrait = class()

local ATE_INTOLERABLE_THOUGHT = 'stonehearth:thoughts:eating:ate_intolerable'

AceFoodPreferenceTrait._ace_old_destroy = FoodPreferenceTrait.destroy
function AceFoodPreferenceTrait:destroy()
   self:_ace_old_destroy()
   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   if thoughts_component then
      thoughts_component:remove_response(self._intolerable_thought_id, ATE_INTOLERABLE_THOUGHT)
   end
end

AceFoodPreferenceTrait._ace_old__load_preferences = FoodPreferenceTrait._load_preferences
function AceFoodPreferenceTrait:_load_preferences()
   self:_ace_old__load_preferences()
   local json = radiant.resources.load_json(self._sv._uri)
   self._food_intolerances = json.data.food_intolerances or ''
   self._intolerable_thought = json.data.intolerable_thought or ATE_INTOLERABLE_THOUGHT
end

AceFoodPreferenceTrait._ace_old__map_thoughts = FoodPreferenceTrait._map_thoughts
function AceFoodPreferenceTrait:_map_thoughts()
   self:_ace_old__map_thoughts()
   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   self._intolerable_thought_id = thoughts_component:add_thought_response(ATE_INTOLERABLE_THOUGHT, self._intolerable_thought)
end

return AceFoodPreferenceTrait
