--[[
   replaced priority with range that takes hunger score into consideration
   so feeding can override other things like sleeping during bad weather
]]

local PetEat = radiant.class()

PetEat.name = 'eat to live, pet version'
PetEat.does = 'stonehearth:eat'
PetEat.args = {}
PetEat.priority = {0, 1}

function PetEat:start_thinking(ai, entity, args)
   if radiant.entities.get_resource(entity, 'calories') == nil then
      ai:set_debug_progress('dead: have no calories resource')
      return
   end

   -- Constant state
   self._ai = ai
   self._entity = entity

   -- Mutable state
   self._ready = false
   local consumption = self._entity:get_component('stonehearth:consumption')
   if consumption then
      self._calorie_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:calories', self, self._rethink)
      self:_rethink()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
   else
      ai:set_debug_progress('dead; has no consumption component')
   end
end

function PetEat:stop_thinking(ai, entity, args)
   if self._calorie_listener then
      self._calorie_listener:destroy()
      self._calorie_listener = nil
   end
end

function PetEat:_rethink()
   local consumption = self._entity:get_component('stonehearth:consumption')
   local hunger_score = consumption:get_hunger_score()
   if consumption:get_hunger_state() >= stonehearth.constants.hunger_levels.HUNGRY then
      self._ai:set_debug_progress('ready; hunger = ' .. hunger_score)
      if not self._ready then
         self._ai:set_think_output()
         self._ready = true
         radiant.events.trigger_async(self._entity, 'stonehearth:entity:looking_for_food')
      end
   else
      self._ai:set_debug_progress('not ready; hunger = ' .. hunger_score)
      if self._ready then
         self._ai:clear_think_output()
         self._ready = false
      end
   end

   self._ai:set_utility(hunger_score)
end

local ai = stonehearth.ai
return ai:create_compound_action(PetEat)
         :execute('stonehearth:pet_eat_directly')
