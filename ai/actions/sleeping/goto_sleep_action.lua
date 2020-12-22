--[[
   override to not try to sleep while following a shepherd, and to cancel sleeping when a shepherd calls
]]

local GoToSleep = radiant.class()

GoToSleep.name = 'go to sleep'
GoToSleep.does = 'stonehearth:goto_sleep'
GoToSleep.args = {}
GoToSleep.priority = {0, 1}

local log = radiant.log.create_logger('goto_sleep_action')

function GoToSleep:start_thinking(ai, entity, args)
   if radiant.entities.get_resource(entity, 'sleepiness') == nil then
      ai:set_debug_progress('dead: have no sleepiness resource')
      return
   end

   --log:debug('%s start_thinking', entity)

   self._ai = ai
   self._entity = entity
   self._bedtime_start = self:_get_bedtime(false)
   self._bedtime_end = self:_get_bedtime(true)
   self._ready = false
   self._sleepiness_listener = radiant.events.listen(entity, 'stonehearth:expendable_resource_changed:sleepiness', self, self._rethink)
   self._bedtime_start_alarm = stonehearth.calendar:set_alarm(self._bedtime_start, function()
         self._bedtime_timer = stonehearth.calendar:set_interval("bedtime timer", '10m', function()
            self:_rethink()
         end)
         self:_rethink()
      end)
   self._bedtime_end_alarm = stonehearth.calendar:set_alarm(self._bedtime_end, function()
         if self._bedtime_timer then
            self._bedtime_timer:destroy()
            self._bedtime_timer = nil
         end
         self:_rethink()
      end)
   self:_rethink()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
end

function GoToSleep:stop_thinking(ai, entity, args)
   --log:debug('%s stop_thinking', entity)
   self._bedtime_start = nil
   self._bedtime_end = nil
   self._ready = false
   if self._sleepiness_listener then
      self._sleepiness_listener:destroy()
      self._sleepiness_listener = nil
   end
   if self._bedtime_start_alarm then
      self._bedtime_start_alarm:destroy()
      self._bedtime_start_alarm = nil
   end
   if self._bedtime_end_alarm then
      self._bedtime_end_alarm:destroy()
      self._bedtime_end_alarm = nil
   end
   if self._bedtime_timer then
      self._bedtime_timer:destroy()
      self._bedtime_timer = nil
   end
end

function GoToSleep:_rethink()
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

   -- make sure we're not a pasture animal currently following a shepherd
   local equipment_component = self._entity:get_component('stonehearth:equipment')
   local pasture_tag = equipment_component and equipment_component:has_item_type('stonehearth:pasture_equipment:tag')
   local shepherded_animal_component = pasture_tag and pasture_tag:get_component('stonehearth:shepherded_animal')
   if shepherded_animal_component and shepherded_animal_component:get_following() then
      self._ai:set_utility(0)
      if self._ready then
         self._ai:clear_think_output()
         self._ready = false
      end
      return
   end

   -- Our decision is mainly based on the sleepiness resource.
   local resources = self._entity:get_component('stonehearth:expendable_resources')
   local raw_sleepiness = resources:get_value('sleepiness')
   local sleepiness = raw_sleepiness

   -- Effective sleepiness is augmented by whether it's bedtime.
   local now = stonehearth.calendar:get_seconds_since_last_midnight()
   local bedtime_end = self._bedtime_end
   local seconds_in_day = stonehearth.calendar:get_time_durations().day
   if bedtime_end < self._bedtime_start then
      bedtime_end = bedtime_end + seconds_in_day
   end
   if now < self._bedtime_start then
      now = now + seconds_in_day
   end
   local is_bedtime = now >= self._bedtime_start and now <= bedtime_end
   if is_bedtime then
      local progress = math.min(1.0, (now - self._bedtime_start) / stonehearth.calendar:get_time_durations().hour)  -- Rise gradually over an hour.
      sleepiness = sleepiness + progress * stonehearth.constants.sleep.BEDTIME_SLEEPINESS_BOOST
   end
   
   -- Make the decision.
   local min_sleepiness_to_sleep = stonehearth.constants.sleep.MIN_SLEEPINESS_TO_SLEEP
   local max_sleepiness = resources:get_max_value('sleepiness')
   if sleepiness >= min_sleepiness_to_sleep then
      if not self._ready then
         local sleepiness_severity = (math.min(sleepiness, max_sleepiness) - min_sleepiness_to_sleep) / (max_sleepiness - min_sleepiness_to_sleep)
         self._ready = true
         self._ai:set_think_output()
         self._ai:set_utility(sleepiness_severity)
      end
   else
      if self._ready then
         self._ready = false
         self._ai:clear_think_output()
         self._ai:set_utility(0)
      end
   end

   if self._ai then -- Could be cleared due to clear_think_output()
      self._ai:set_debug_progress(radiant.util.format_string('sleepiness =  %d / [%d - %d]; bedtime = %s; ready = %s',
                                                             raw_sleepiness, min_sleepiness_to_sleep, max_sleepiness, is_bedtime, self._ready))
   end
end

function GoToSleep:_get_bedtime(is_end)  -- in seconds since midnight
   local hour = is_end and stonehearth.constants.sleep.BEDTIME_END_HOUR
                        or stonehearth.constants.sleep.BEDTIME_START_HOUR
                        
   local attributes = self._entity:get_component('stonehearth:attributes')
   if attributes then
      local wake_up_time_modifier = attributes:get_attribute('wake_up_time_modifier', 0)
      if wake_up_time_modifier ~= 0 then
         hour = hour + wake_up_time_modifier
      end
   end

   return hour * stonehearth.calendar:get_time_durations().hour
end

local ai = stonehearth.ai
return ai:create_compound_action(GoToSleep)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:pasture_animal_following_shepherd',
         })
         :execute('stonehearth:sleep')
