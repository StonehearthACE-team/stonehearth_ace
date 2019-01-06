local EatFeedAdjacent = require 'stonehearth.ai.actions.pasture_animal.eat_feed_adjacent_action'

local AceEatFeedAdjacent = class()

AceEatFeedAdjacent._old_stop = EatFeedAdjacent.stop
function AceEatFeedAdjacent:stop(ai, entity, args)
   local quality_chances
   
   if self._animal_feed_data then
      local animal_feed = radiant.entities.get_entity_data(args.food, 'stonehearth_ace:animal_feed')
      quality_chances = animal_feed and animal_feed.quality_chances
   end

   self:_old_stop(ai, entity, args)

   if quality_chances then
      item_quality_lib.apply_random_quality(entity, quality_chances, true)
   end
end

return AceEatFeedAdjacent
