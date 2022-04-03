local EatFeedAdjacent = require 'stonehearth.ai.actions.pasture_animal.eat_feed_adjacent_action'

local AceEatFeedAdjacent = class()

AceEatFeedAdjacent._ace_old_stop = EatFeedAdjacent.stop
function AceEatFeedAdjacent:stop(ai, entity, args)
   local quality_chances
   
   if self._animal_feed_data then
      local animal_feed = radiant.entities.get_entity_data(args.food, 'stonehearth_ace:animal_feed')
      quality_chances = animal_feed and animal_feed.quality_chances

      -- Add the feed buff, if any
		if self._animal_feed_data.applied_buffs then
			for _, applied_buff in ipairs(self._animal_feed_data.applied_buffs) do
				radiant.entities.add_buff(entity, applied_buff)
			end
		end
   end

   self:_ace_old_stop(ai, entity, args)

   if quality_chances then
      item_quality_lib.apply_random_quality(entity, quality_chances,
            {max_quality = item_quality_lib.get_max_random_quality(entity:get_player_id())})
   end
end

return AceEatFeedAdjacent
