local ShepherdedAnimalComponent = require 'stonehearth.components.shepherd_pasture.shepherded_animal_component'
local AceShepherdedAnimalComponent = class()

AceShepherdedAnimalComponent._ace_old_set_following = ShepherdedAnimalComponent.set_following
function AceShepherdedAnimalComponent:set_following(should_follow, shepherd)
   -- if we're being set to follow a shepherd, clear sleepiness
   if should_follow and shepherd then
      radiant.events.trigger_async(self._sv.animal, 'stonehearth_ace:pasture_animal_following_shepherd')
      -- local expendable = self._sv.animal:get_component('stonehearth:expendable_resources')
      -- local sleepiness = expendable and expendable:get_value('sleepiness')
      -- if sleepiness then
      --    expendable:set_value('sleepiness', math.max(sleepiness, stonehearth.constants.sleep.SLEEP_ON_GROUND_RESTED_SLEEPINESS))
      -- end
   end
   
   self:_ace_old_set_following(should_follow, shepherd)
end

return AceShepherdedAnimalComponent
