local constants = require 'stonehearth.constants'
local rng = _radiant.math.get_default_rng()

local AceConversationManager = class()

function AceConversationManager:_produce_conversation_results()
   local result, sentiment
   local tally = 0
   local num_reactions = 0
   for _, participant_sentiment in pairs(self._reactions) do
      -- if anyone was neutral, this is neither an agreement or disagreement
      if participant_sentiment == 0 then
         result = constants.conversation.result.INDIFFERENT
         break
      end
      tally = tally + participant_sentiment
      num_reactions = num_reactions + 1
   end

   if not result then
      if num_reactions > 0 then
         -- everyone had the same sentiment, they were in agreement
         if math.abs(tally) == num_reactions then
            result = constants.conversation.result.AGREEMENT
            sentiment = (tally > 0) and constants.sentiment.POSITIVE or constants.sentiment.NEGATIVE
         else
            result = constants.conversation.result.DISAGREEMENT
         end
      else
         -- give it a random result
         local rnd = rng:get_int(-1, 2)
         if rnd < 0 then
            result = constants.conversation.result.DISAGREEMENT
         elseif rnd == 0 then
            result = constants.conversation.result.INDIFFERENT
         else
            result = constants.conversation.result.AGREEMENT
            sentiment = rng:get_int(0, 1) == 1 and constants.sentiment.POSITIVE or constants.sentiment.NEGATIVE
         end
      end
   end

   self._conversation_result = {
      result = result,
      sentiment = sentiment
   }

   for _, participant in pairs(self._participants) do
      -- traits can listen on this and update their target's resulting thought if appropriate
      radiant.events.trigger(participant, 'stonehearth:conversation:results_produced', { conversation_result = self._conversation_result })
   end
end

return AceConversationManager
