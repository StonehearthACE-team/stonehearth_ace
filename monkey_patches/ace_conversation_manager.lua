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

-- ACE: additionally (conditionally) add positive thoughts based on the renown of the conversation target
function AceConversationManager:_add_conversation_thoughts()
   local result = self._conversation_result.result
   for _, participant in pairs(self._participants) do
      local target_name
      local target = stonehearth.conversation:get_target(participant)
      if target and target:is_valid() then
         target_name = radiant.entities.get_custom_name(target)
      end

      local options = {
         tooltip_args = {
            --TODO/Fix: this doesn't update in the thought if the target's name changes later
            target_name = target_name
         }
      }

      -- add default outcome-based thoughts
      local thought_key = constants.conversation.THOUGHTS[result]

      -- add default outcome-based thoughts
      -- conversations that didn't end in agreement or disagreement generate no thoughts
      if thought_key then
         radiant.entities.add_thought(participant, thought_key, options)
      end

      self:_add_renown_thought(participant, target, options)
   end
end

function AceConversationManager:_add_renown_thought(participant, target, options)
   local reaction = self._reactions[participant:get_id()]
   if reaction and reaction > 0 then
      -- sentiment was positive for this participant, so check the renown of their target
      local renown = radiant.entities.get_renown(target)
      local is_lower
      if renown < radiant.entities.get_renown(participant) then
         is_lower = true
      end
      if renown then
         -- this could be done with an easily customizable array of tiers, but it's not that important to customize?
         local renown_levels = constants.conversation.renown_thresholds
         local level
         if renown >= renown_levels.VERY_HIGH then
            level = renown_levels.VERY_HIGH
         elseif renown >= renown_levels.HIGH then
            level = renown_levels.HIGH
         elseif renown >= renown_levels.MEDIUM then
            level = renown_levels.MEDIUM
         elseif renown >= renown_levels.LOW or is_lower then
            level = renown_levels.LOW
         end

         local thought_key = is_lower and level and constants.conversation.RENOWN_THOUGHTS[level] .. '_lower' or level and constants.conversation.RENOWN_THOUGHTS[level]
         if thought_key then
            radiant.entities.add_thought(participant, thought_key, options)
         end
      end
   end
end

return AceConversationManager
