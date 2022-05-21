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
      local target_renown = radiant.entities.get_renown(target) or 0
      local min_renown = constants.conversation.MIN_TARGET_RENOWN

      if target_renown >= min_renown then
         local thresholds = constants.conversation.RENOWN_THRESHOLDS
         local thought_keys = constants.conversation.RENOWN_THOUGHTS

         local renown = radiant.entities.get_renown(participant) or 0
         local threshold = target_renown / math.max(renown, min_renown)
         local thought_key

         -- thresholds are named for the target's renown relative to this participant's renown
         -- e.g., MUCH_LOWER means the participant is talking to a target of much lower renown than the participant
         if renown < thresholds.MUCH_LOWER then
            thought_key = thought_keys.MUCH_LOWER
         elseif renown < thresholds.LOWER then
            thought_key = thought_keys.LOWER
         elseif renown < thresholds.SOME_LOWER then
            thought_key = thought_keys.SOME_LOWER
         elseif renown <= thresholds.EQUAL then
            thought_key = thought_keys.EQUAL
         elseif renown <= thresholds.SOME_HIGHER then
            thought_key = thought_keys.SOME_HIGHER
         elseif renown <= thresholds.HIGHER then
            thought_key = thought_keys.HIGHER
         else
            thought_key = thought_keys.MUCH_HIGHER
         end

         if thought_key then
            radiant.entities.add_thought(participant, thought_key, options)
         end
      end
   end
end

return AceConversationManager
