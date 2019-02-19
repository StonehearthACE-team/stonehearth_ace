local FoodIntoleranceTrait = class()

local ATE_INTOLERABLE_THOUGHT = 'stonehearth:thoughts:eating:ate_intolerable'

function FoodIntoleranceTrait:initialize()
   self._sv._entity = nil
   self._sv._uri = nil
   self._food_intolerances = ''
   self._intolerable_thought = ''
   self._intolerable_thought_id = -1
end

function FoodIntoleranceTrait:create(entity, uri)
   self._sv._entity = entity
   self._sv._uri = uri

   self:_load_intolerances()
end

function FoodIntoleranceTrait:restore()
   self:_load_intolerances()
end

function FoodIntoleranceTrait:activate()
   local consumption = self._sv._entity:get_component('stonehearth:consumption')
   if consumption then
      consumption:set_food_intolerances(self._food_intolerances)
   end

   self:_map_thoughts()
end

function FoodIntoleranceTrait:destroy()
   if self._on_eat_listener then
      self._on_eat_listener:destroy()
      self._on_eat_listener = nil
   end

   local consumption = self._sv._entity:get_component('stonehearth:consumption')
   if consumption then
      consumption:set_food_intolerances('')
   end

   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   if thoughts_component then
      thoughts_component:remove_response(self._intolerable_thought_id, ATE_INTOLERABLE_THOUGHT)
   end
end

function FoodIntoleranceTrait:_load_intolerances()
   local json = radiant.resources.load_json(self._sv._uri)
   self._food_intolerances = json.data.food_intolerances or ''
   self._intolerable_thought = json.data.intolerable_thought or ATE_INTOLERABLE_THOUGHT
end

function FoodIntoleranceTrait:_map_thoughts()
   local thoughts_component = self._sv._entity:get_component('stonehearth:thoughts')
   self._intolerable_thought_id = thoughts_component:add_thought_response(ATE_INTOLERABLE_THOUGHT, self._intolerable_thought)
end

return FoodIntoleranceTrait
