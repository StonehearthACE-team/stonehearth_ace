local EatingLib = require 'stonehearth.ai.lib.eating_lib'

local Eat = radiant.class()

Eat.name = 'eat to live'
Eat.status_text_key = 'stonehearth:ai.actions.status_text.eat' -- eat item will override this when it runs
Eat.does = 'stonehearth:eat'
Eat.args = {}
Eat.priority = {0, 1}

local log = radiant.log.create_logger('eat_action')

function Eat:start_thinking(ai, entity, args)
   if radiant.entities.get_resource(entity, 'calories') == nil then
      ai:set_debug_progress('dead: have no calories resource')
      return
   end

   --log:debug('%s start_thinking', entity)

   -- Constant state
   self._ai = ai
   self._entity = entity

   -- Mutable state
   self._ready = false
   self._started = false
   local consumption = self._entity:get_component('stonehearth:consumption')
   self._food_preferences = consumption:get_food_preferences()
   self._food_intolerances = consumption:get_food_intolerances()
   self._food_filter_fn = EatingLib.make_food_filter()
   
   self._hour_type = nil
   self._weather_type = nil

   self._calorie_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:calories', self, self._rethink)
   self._marked_unready_listener = radiant.events.listen(self._entity, 'stonehearth_ace:entity:looking_for_food:marked_unready', self, self._rethink)
   self._timer = stonehearth.calendar:set_interval("eat_action hourly", '25m+5m', function() self:_reconsider_filter() end)
   self:_reconsider_filter()
end

function Eat:stop_thinking(ai, entity, args)
   --log:debug('%s stop_thinking', entity)
   if self._calorie_listener then
      self._calorie_listener:destroy()
      self._calorie_listener = nil
   end
   if self._marked_unready_listener then
      self._marked_unready_listener:destroy()
      self._marked_unready_listener = nil
   end
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
end

function Eat:start(ai, entity, args)
   self._started = true
end

function Eat:stop(ai, entity, args)
   radiant.events.trigger_async(self._entity, 'stonehearth:entity:stopped_looking_for_food')
end

function Eat:_reconsider_filter()
   local hour_type = EatingLib.get_current_hour_type()
   local weather_type = stonehearth.weather:get_current_weather_type()

   if hour_type ~= self._hour_type or weather_type ~= self._weather_type then
      --log:debug('%s reconsidering filter at hour %s and weather %s', self._entity, tostring(hour_type), tostring(weather_type))
      self._hour_type = hour_type
      self._weather_type = weather_type

      --self._food_filter_fn = EatingLib.make_food_filter(self._food_preferences, self._food_intolerances, hour_type, weather_type)
      local consumption = self._entity:get_component('stonehearth:consumption')
      if consumption:distinguishes_food_quality() then
         self._food_rating_fn = EatingLib.make_food_rater(self._food_preferences, self._food_intolerances, hour_type, weather_type)
      else
         self._food_rating_fn = nil
      end

      if not self._ready then
         self:_rethink()
      else
         self:_mark_unready(true)
      end
   else
      self:_rethink()
   end
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
   --log:debug('%s marking ready (currently %s)', self._entity, tostring(self._ready))
   if not self._ready then
      self._ready = true
      self._ai:set_think_output({
         food_filter_fn = self._food_filter_fn,
         food_rating_fn = self._food_rating_fn,
      })
      radiant.events.trigger_async(self._entity, 'stonehearth:entity:looking_for_food')
   end
end

function Eat:_mark_unready(reconsidering)
   --log:debug('%s marking unready (currently %s)', self._entity, tostring(self._ready))
   if not self._started and self._ready then
      self._ready = false
      self._ai:clear_think_output()

      if reconsidering then
         radiant.events.trigger_async(self._entity, 'stonehearth_ace:entity:looking_for_food:marked_unready')
      else
         radiant.events.trigger_async(self._entity, 'stonehearth:entity:stopped_looking_for_food')
      end
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(Eat)
         :execute('stonehearth:get_food', {
            food_filter_fn = ai.PREV.food_filter_fn,
            food_rating_fn = ai.PREV.food_rating_fn,
         })
         :execute('stonehearth:find_seat_and_eat')
