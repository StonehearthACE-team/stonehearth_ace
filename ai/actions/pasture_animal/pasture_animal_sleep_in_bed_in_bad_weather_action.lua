local PastureAnimalSleepInBedInBadWeather = radiant.class()

PastureAnimalSleepInBedInBadWeather.name = 'sleep in bad weather'
PastureAnimalSleepInBedInBadWeather.does = 'stonehearth:goto_sleep'
PastureAnimalSleepInBedInBadWeather.args = {}
PastureAnimalSleepInBedInBadWeather.priority = 0.5

function PastureAnimalSleepInBedInBadWeather:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._ready = false
   self._weather_listener = radiant.events.listen(radiant, 'stonehearth_ace:weather_state_started', self, self._rethink)
   self:_rethink()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
end

function PastureAnimalSleepInBedInBadWeather:stop_thinking(ai, entity, args)
   self._ready = false
   if self._weather_listener then
      self._weather_listener:destroy()
      self._weather_listener = nil
   end
   self:_destroy_recheck_timer()
end

function PastureAnimalSleepInBedInBadWeather:_destroy_recheck_timer()
   if self._recheck_timer then
      self._recheck_timer:destroy()
      self._recheck_timer = nil
   end
end

function PastureAnimalSleepInBedInBadWeather:_rethink()
   if not self._entity or not self._entity:is_valid() then
      return -- Events might be delivered after the entity has died.
   end

   -- Make sure we aren't incapacitated.
   local ic = self._entity:get_component('stonehearth:incapacitation')
   if ic and ic:is_incapacitated() then
      self._ai:set_utility(0)
      if self._ready then
         self._ai:clear_think_output()
         self._ready = false
      end
      return
   end

   -- Make the decision.
   local weather = stonehearth.weather:get_current_weather()
   local debuffs = weather:get_unsheltered_animal_debuffs()
   if debuffs then
      for _, debuff in ipairs(debuffs) do
         local json = radiant.resources.load_json(debuff)
         if json and json.axis == 'debuff' then
            -- set a timer to keep retrying in case they get up to eat or something else
            if not self._recheck_timer then
               self._recheck_timer = stonehearth.calendar:set_interval("bad weather bed timer", '10m', function()
                  self:_rethink()
               end)
            end
            if not self._ready then
               self._ready = true
               self._ai:set_think_output()
            end
            return
         end
      end
   end

   self:_destroy_recheck_timer()
   if self._ready then
      self._ready = false
      self._ai:clear_think_output()
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(PastureAnimalSleepInBedInBadWeather)
         :execute('stonehearth_ace:pasture_animal_sleep_in_bed')
