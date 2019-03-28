local Personality = require 'stonehearth.components.personality.personality_component'
local AcePersonality = class()

AcePersonality._ace_old__add_log_entry = Personality._add_log_entry
function AcePersonality:_add_log_entry(entry_title, entry_text, substitution_values, score_metadata)
   local entry = self:_ace_old__add_log_entry(entry_title, entry_text, substitution_values, score_metadata)
   if entry then
      entry.person_custom_data = radiant.entities.get_custom_data(self._entity)
   end

   return entry
end

return AcePersonality
