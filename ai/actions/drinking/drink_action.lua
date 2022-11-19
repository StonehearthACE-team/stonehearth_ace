local DrinkingLib = require 'stonehearth_ace.ai.lib.drinking_lib'

local Drink = class()

Drink.name = 'drink to live'
Drink.status_text_key = 'stonehearth_ace:ai.actions.status_text.drink'
Drink.does = 'stonehearth_ace:drink'
Drink.args = {}
Drink.priority = {0, 1}

local log = radiant.log.create_logger('drink_action')

function Drink:start_thinking(ai, entity, args)
   if radiant.entities.get_resource(entity, 'drink_satiety') == nil then
      ai:set_debug_progress('entity has no drink_satiety resource')
      return
   end

   self._ai = ai
   self._entity = entity

   self._ready = false
   self._started = false
   local consumption = self._entity:get_component('stonehearth:consumption')
   self._drink_preferences = consumption:get_drink_preferences()
   self._drink_intolerances = consumption:get_drink_intolerances()
   
   self._hour_type = nil
   self._weather_type = nil
   self._has_well = nil

   --log:debug('%s start_thinking', entity)

   self:_create_well_listeners()
   self._drink_satiety_listener = radiant.events.listen(self._entity, 'stonehearth:expendable_resource_changed:drink_satiety', self, self._rethink)
   self._marked_unready_listener = radiant.events.listen(self._entity, 'stonehearth_ace:entity:looking_for_drink:marked_unready', self, self._rethink)
   self._timer = stonehearth.calendar:set_interval("drink_action hourly", '25m+5m', function() self:_reconsider_filter() end)
   self:_reconsider_well_existence()
   self:_reconsider_filter()
end

function Drink:stop_thinking(ai, entity, args)
   --log:debug('%s stop_thinking', entity)
   if self._drink_satiety_listener then
      self._drink_satiety_listener:destroy()
      self._drink_satiety_listener = nil
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

function Drink:start(ai, entity, args)
   self._started = true
end

function Drink:stop(ai, entity, args)
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:entity:stopped_looking_for_drink')
end

function Drink:_create_well_listeners()
   local town = stonehearth.town:get_town(self._entity)
   if town then
      self._first_well_registered_listener =
            radiant.events.listen(town, 'stonehearth_ace:town:entity_type_registered_first:stonehearth_ace:well', self, self._reconsider_well_existence)
      self._last_well_unregistered_listener =
            radiant.events.listen(town, 'stonehearth_ace:town:entity_type_unregistered_last:stonehearth_ace:well', self, self._reconsider_well_existence)
   end
end

function Drink:_reconsider_well_existence()
   local town = stonehearth.town:get_town(self._entity)
   self._has_well = town and town:is_entity_type_registered('stonehearth_ace:well')
   -- upgrading your only well can cause this to happen twice in a tick
   -- don't force a reconsider; just set a flag that gets cleared on next reconsider
   --self:_reconsider_filter(true)
   self._has_well_changed = true
end

function Drink:_reconsider_filter()
   local hour_type = DrinkingLib.get_current_hour_type()
   local weather_type = stonehearth.weather:get_current_weather_type()

   if self._has_well_changed or hour_type ~= self._hour_type or weather_type ~= self._weather_type then
      --log:debug('%s reconsidering filter at hour %s (%s) and weather %s (%s)',
      --      self._entity, tostring(hour_type), tostring(self._hour_type), tostring(weather_type), tostring(self._weather_type))
      self._hour_type = hour_type
      self._weather_type = weather_type
      self._has_well_changed = nil

      -- if there's a well, we don't care about complicated filters, but we still want the adjust our rater
      if self._has_well then
         --log:debug('well present, %s using simple drink filter', self._entity)
         self._drink_filter_fn = DrinkingLib.make_simple_drink_filter()
      else
         self._drink_filter_fn = DrinkingLib.make_drink_filter(self._drink_preferences, self._drink_intolerances, hour_type, weather_type)
      end
      local consumption = self._entity:get_component('stonehearth:consumption')
      if consumption:distinguishes_drink_quality() then
         self._drink_rating_fn = DrinkingLib.make_drink_rater(self._drink_preferences, self._drink_intolerances, hour_type, weather_type)
      else
         self._drink_rating_fn = nil -- function(item) return 1 end
      end

      if not self._ready then
         self:_rethink()
      else
         self:_mark_unready()
      end
   else
      self:_rethink()
   end
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
   --log:debug('%s marking ready (currently %s)', self._entity, tostring(self._ready))
   if not self._ready then
      self._ready = true
      --log:debug('%s ready to drink with rating function %s', self._entity, tostring(self._drink_rating_fn))
      self._ai:set_think_output({
         drink_filter_fn = self._drink_filter_fn,
         drink_rating_fn = self._drink_rating_fn,
      })
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:entity:looking_for_drink')
   end
end

function Drink:_mark_unready()
   --log:debug('%s marking unready (currently %s)', self._entity, tostring(self._ready))
   if not self._started and self._ready then
      self._ready = false
      self._ai:clear_think_output()
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:entity:looking_for_drink:marked_unready')
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(Drink)
         :execute('stonehearth_ace:get_drink', {
            drink_filter_fn = ai.PREV.drink_filter_fn,
            drink_rating_fn = ai.PREV.drink_rating_fn,
         })
         :execute('stonehearth_ace:find_seat_and_drink')
