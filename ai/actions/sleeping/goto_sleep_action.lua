--[[
   override to not try to sleep while following a shepherd, and to cancel sleeping when a shepherd calls
]]

local sleeping_lib = require 'stonehearth_ace.ai.lib.sleeping_lib'

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
   self._bedtime_start = sleeping_lib.get_bedtime(entity, false)
   self._bedtime_end = sleeping_lib.get_bedtime(entity, true)
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

   -- check if we're already sleeping (i.e., just loaded the game)
   local sleepiness_observer = radiant.entities.get_observer(self._entity, 'stonehearth:observers:sleepiness')
   if sleepiness_observer:is_asleep() then
      if not self._ready then
         self._ready = true
         self._ai:set_think_output()
         self._ai:set_utility(1)
         return
      end
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

   local sleepiness, raw_sleepiness, is_bedtime = sleeping_lib.get_current_sleepiness(self._entity, self._bedtime_start, self._bedtime_end)
   
   -- Make the decision.
   local min_sleepiness_to_sleep = stonehearth.constants.sleep.MIN_SLEEPINESS_TO_SLEEP
   local max_sleepiness = self._entity:get_component('stonehearth:expendable_resources'):get_max_value('sleepiness')
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

local ai = stonehearth.ai
return ai:create_compound_action(GoToSleep)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:pasture_animal_following_shepherd',
         })
         :execute('stonehearth:sleep')
