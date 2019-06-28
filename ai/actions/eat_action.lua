local EatingLib = require 'stonehearth.ai.lib.eating_lib'

local Eat = radiant.class()

Eat.name = 'eat to live'
Eat.status_text_key = 'stonehearth:ai.actions.status_text.eat' -- eat item will override this when it runs
Eat.does = 'stonehearth:eat'
Eat.args = {}
Eat.priority = {0, 1}

function Eat:start_thinking(ai, entity, args)
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
   local food_preferences = consumption:get_food_preferences()
	local food_intolerances = consumption:get_food_intolerances()
   self._food_filter_fn = EatingLib.make_food_filter(food_preferences, food_intolerances)
   self._food_rating_fn = consumption:distinguishes_food_quality() and EatingLib.make_food_rater(food_preferences, food_intolerances) or function(item) return 1 end

   self._calorie_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:calories', self, self._rethink)
   self._timer = stonehearth.calendar:set_interval("eat_action hourly", '10m+5m', function() self:_rethink() end, '20m')
   self:_rethink()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
end

function Eat:stop_thinking(ai, entity, args)
   if self._calorie_listener then
      self._calorie_listener:destroy()
      self._calorie_listener = nil
   end
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
end

function Eat:stop(ai, entity, args)
   radiant.events.trigger_async(self._entity, 'stonehearth:entity:stopped_looking_for_food')
end

function Eat:_rethink()
   local consumption = self._entity:get_component('stonehearth:consumption')
   local hunger_score = consumption:get_hunger_score()
   local min_hunger_to_eat = consumption:get_min_hunger_to_eat_now()

   self._ai:set_debug_progress(string.format('hunger = %s; min to eat now = %s', hunger_score, min_hunger_to_eat))
   if hunger_score >= min_hunger_to_eat then
      self:_mark_ready()
   else
      self:_mark_unready()
   end

   self._ai:set_utility(hunger_score)
end

function Eat:_mark_ready()
   if not self._ready then
      self._ready = true
      self._ai:set_think_output({
         food_filter_fn = self._food_filter_fn,
         food_rating_fn = self._food_rating_fn,
      })
      radiant.events.trigger_async(self._entity, 'stonehearth:entity:looking_for_food')
   end
end

function Eat:_mark_unready()
   if self._ready then
      self._ready = false
      self._ai:clear_think_output()
      radiant.events.trigger_async(self._entity, 'stonehearth:entity:stopped_looking_for_food')
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(Eat)
         :execute('stonehearth:get_food', {
            food_filter_fn = ai.PREV.food_filter_fn,
            food_rating_fn = ai.PREV.food_rating_fn,
         })
         :execute('stonehearth:find_seat_and_eat')
