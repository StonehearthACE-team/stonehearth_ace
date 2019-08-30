local rng = _radiant.math.get_default_rng()

local SleepinessObserver = require 'stonehearth.ai.observers.sleepiness_observer'
local AceSleepinessObserver = class()

AceSleepinessObserver._ace_old_initialize = SleepinessObserver.initialize
function AceSleepinessObserver:initialize()
   self._sv.asleep = nil
	
   self:_ace_old_initialize()
end

AceSleepinessObserver._ace_old__on_hourly = SleepinessObserver._on_hourly
function AceSleepinessObserver:_on_hourly()	
	if not self._sv.asleep then
		self:_ace_old__on_hourly()
		
		local sleepiness = self._expendable_resources_component:get_value('sleepiness')	
		if sleepiness then
			self:_add_sleepiness_thoughts(sleepiness)
		end
	else
		local attributes_component = self._entity:get_component('stonehearth:attributes')
		local spirit = attributes_component:get_attribute('spirit')
		local dream_type = rng:get_int(1, 10) + spirit
		if dream_type < 8 then
			radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleepiness:bad_dream')
		elseif dream_type > 8 then
			radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleepiness:good_dream')
		else
			radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleepiness:neutral')
		end
	end
end

AceSleepinessObserver._ace_old__add_sleepiness_thoughts = SleepinessObserver._add_sleepiness_thoughts
function AceSleepinessObserver:_add_sleepiness_thoughts(sleepiness)
   if sleepiness > stonehearth.constants.sleep.EXHAUSTED_THOUGHT_THRESHOLD then
      radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleepiness:exhausted')
   else
      self:_ace_old__add_sleepiness_thoughts(sleepiness)
   end
end

AceSleepinessObserver._ace_old_start_sleeping = SleepinessObserver.start_sleeping
function AceSleepinessObserver:start_sleeping(bed)
	self._sv.asleep = true
	return self:_ace_old_start_sleeping(bed)
end

AceSleepinessObserver._ace_old_finish_sleeping = SleepinessObserver.finish_sleeping
function AceSleepinessObserver:finish_sleeping()
	self:_ace_old_finish_sleeping()
	self._sv.asleep = nil
	radiant.entities.remove_thought(self._entity, 'stonehearth:thoughts:sleepiness:good_dream')
	radiant.entities.remove_thought(self._entity, 'stonehearth:thoughts:sleepiness:bad_dream')
end

return AceSleepinessObserver