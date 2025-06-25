local rng = _radiant.math.get_default_rng()

local SleepinessObserver = require 'stonehearth.ai.observers.sleepiness_observer'
local AceSleepinessObserver = class()

function AceSleepinessObserver:is_asleep()
   return self._sv.asleep
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

function AceSleepinessObserver:_add_finished_sleeping_thoughts(bed, slept_outside, has_roommate)
   if bed then
      local bed_data = radiant.entities.get_entity_data(bed, 'stonehearth:bed')
	  local ownable_component = bed:get_component('stonehearth:ownable_object')
	  local traits_component = self._entity:get_component('stonehearth:traits')
      if bed_data and bed_data.shelter.score > stonehearth.constants.score.shelter.COMFY_BED_THRESHOLD then
         radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleeping:slept_in_comfy_bed')
      end

	  -- ACE: Adding support for barracks' bed
      local is_owner = self:_owns_bed(bed)
      if not is_owner then
		if ownable_component and ownable_component:get_reservation_type() == stonehearth.constants.combat.MILITARY_OWNERSHIP_TYPE then
         	radiant.entities.add_thought(self._entity, 'stonehearth_ace:thoughts:sleeping:slept_in_shared_bed_military')
		else
			radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleeping:slept_in_shared_bed')
		end
      end

      -- Switching the thought to a positive one as a result of this thread: https://discourse.stonehearth.net/t/slept-in-a-shared-room-shouldnt-be-a-thing/31368/25
	  -- ACE: Adding it for Hearthlings with the 'Loner' trait
	  local loner = traits_component and traits_component:has_trait('stonehearth:traits:loner')
      if has_roommate and loner then
         radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleeping:slept_in_shared_room')
      end

      if is_owner and not slept_outside and not has_roommate then
         radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleeping:well_rested')
      end

      if slept_outside then
         -- We don't think this when sleeping outside on the ground.
         -- We let slept_on_ground takes care of that since the player currently has no ability
         -- to control whether hearthlings sleep inside or outside on the ground.
		 -- ACE: Add a "Move to shelter" before they fall asleep on the ground so we can have both debuffs? >:) It would also fix some funny things like lings sleeping in the water or on construction sites since they'd try going somewhere covered...
         radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleeping:slept_outside')
      end
   else
      radiant.entities.add_thought(self._entity, 'stonehearth:thoughts:sleeping:slept_on_ground')
   end
end

return AceSleepinessObserver