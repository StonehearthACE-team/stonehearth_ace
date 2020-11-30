local constants = require 'stonehearth.constants'
local rng = _radiant.math.get_default_rng()

local AceDefaultConversationScript = class()

function AceDefaultConversationScript:get_stages(conversation_manager)
   -- pick a random conversation type
   -- TODO: make it depend on (or be weighted by) the initiator's social needs?
   -- local initiator = conversation_manager:get_initiator()

   -- TODO: have different social_satisfaction scores for each conversation type?

   local type = rng:get_int(1, 3)
   if type == 1 then
      return constants.conversation.DEFAULT_STAGES
   elseif type == 2 then
      return constants.conversation.MEDIUM_STAGES
   else
      return constants.conversation.SHORT_STAGES
   end
end

return AceDefaultConversationScript
