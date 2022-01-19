local sleeping_lib = {}

function sleeping_lib.is_sleepy_enough_to_sleep(entity, bedtime_start, bedtime_end)
   local min_sleepiness_to_sleep = stonehearth.constants.sleep.MIN_SLEEPINESS_TO_SLEEP
   local sleepiness = sleeping_lib.get_current_sleepiness(entity, bedtime_start, bedtime_end)

   return sleepiness > min_sleepiness_to_sleep
end

function sleeping_lib.get_current_sleepiness(entity, bedtime_start, bedtime_end)
   if not bedtime_start then
      bedtime_start = sleeping_lib.get_bedtime(entity, false)
   end
   if not bedtime_end then
      bedtime_end = sleeping_lib.get_bedtime(entity, true)
   end
   
   -- Our decision is mainly based on the sleepiness resource.
   local resources = entity:get_component('stonehearth:expendable_resources')
   local raw_sleepiness = resources:get_value('sleepiness')
   local sleepiness = raw_sleepiness

   -- Effective sleepiness is augmented by whether it's bedtime.
   local now = stonehearth.calendar:get_seconds_since_last_midnight()
   local seconds_in_day = stonehearth.calendar:get_time_durations().day
   if bedtime_end < bedtime_start then
      bedtime_end = bedtime_end + seconds_in_day
   end
   if now < bedtime_start then
      now = now + seconds_in_day
   end
   local is_bedtime = now >= bedtime_start and now <= bedtime_end
   if is_bedtime then
      local progress = math.min(1.0, (now - bedtime_start) / stonehearth.calendar:get_time_durations().hour)  -- Rise gradually over an hour.
      sleepiness = sleepiness + progress * stonehearth.constants.sleep.BEDTIME_SLEEPINESS_BOOST
   end
   
   return sleepiness, raw_sleepiness, is_bedtime
end

function sleeping_lib.get_bedtime(entity, is_end)  -- in seconds since midnight
   local hour = is_end and stonehearth.constants.sleep.BEDTIME_END_HOUR
                        or stonehearth.constants.sleep.BEDTIME_START_HOUR
                        
   local attributes = entity:get_component('stonehearth:attributes')
   if attributes then
      local wake_up_time_modifier = attributes:get_attribute('wake_up_time_modifier', 0)
      if wake_up_time_modifier ~= 0 then
         hour = hour + wake_up_time_modifier
      end
   end

   return hour * stonehearth.calendar:get_time_durations().hour
end

return sleeping_lib
