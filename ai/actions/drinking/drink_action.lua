local DrinkingLib = require 'stonehearth_ace.ai.lib.drinking_lib'

local Drink = class()

Drink.name = 'drink to live'
Drink.status_text_key = 'stonehearth_ace:ai.actions.status_text.drink'
Drink.does = 'stonehearth_ace:drink'
Drink.args = {}
Drink.priority = {0, 1}

function Drink:start_thinking(ai, entity, args)
   if radiant.entities.get_resource(entity, 'drink_satiety') == nil then
      ai:set_debug_progress('entity has no drink_satiety resource')
      return
   end

   self._ai = ai
   self._entity = entity

   self._ready = false
   local consumption = self._entity:get_component('stonehearth:consumption')
   local drink_preferences = consumption:get_drink_preferences()
	local drink_intolerances = consumption:get_drink_intolerances()
   self._drink_filter_fn = DrinkingLib.make_drink_filter(drink_preferences, drink_intolerances)
   self._drink_rating_fn = consumption:distinguishes_drink_quality() and DrinkingLib.make_drink_rater(drink_preferences, drink_intolerances) or function(item) return 1 end

   self._drink_satiety_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:drink_satiety', self, self._rethink)
   self._timer = stonehearth.calendar:set_interval("drink_action hourly", '10m+5m', function() self:_rethink() end, '20m')
   self:_rethink() 
end

function Drink:stop_thinking(ai, entity, args)
   if self._drink_satiety_listener then
      self._drink_satiety_listener:destroy()
      self._drink_satiety_listener = nil
   end
   if self._timer then
      self._timer:destroy()
      self._timer = nil
   end
end

function Drink:stop(ai, entity, args)
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:entity:stopped_looking_for_drink')
end

function Drink:_rethink()
   local consumption = self._entity:get_component('stonehearth:consumption')
   local thirst_score = consumption:get_thirst_score()
   local min_thirst_to_drink = consumption:get_min_thirst_to_drink_now()

   self._ai:set_debug_progress(string.format('thirst = %s; min to drink now = %s', thirst_score, min_thirst_to_drink))
   if thirst_score >= min_thirst_to_drink then
      self:_mark_ready()
   else
      self:_mark_unready()
   end

   self._ai:set_utility(thirst_score)
end

function Drink:_mark_ready()
   if not self._ready then
      self._ready = true
      self._ai:set_think_output({
         drink_filter_fn = self._drink_filter_fn,
         drink_rating_fn = self._drink_rating_fn,
      })
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:entity:looking_for_drink')
   end
end

function Drink:_mark_unready()
   if self._ready then
      self._ready = false
      self._ai:clear_think_output()
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:entity:stopped_looking_for_drink')
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(Drink)
         :execute('stonehearth_ace:get_drink', {
            drink_filter_fn = ai.PREV.drink_filter_fn,
            drink_rating_fn = ai.PREV.drink_rating_fn,
         })
         :execute('stonehearth_ace:find_seat_and_drink')
