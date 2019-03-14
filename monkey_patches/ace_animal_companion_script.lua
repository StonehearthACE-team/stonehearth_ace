local AnimalCompanionScript = require 'stonehearth.data.traits.animal_companion.animal_companion_script'
local AceAnimalCompanionScript = class()

AceAnimalCompanionScript._ace_old__set_name_text = AnimalCompanionScript._set_name_text
function AceAnimalCompanionScript:_set_name_text(target, role)
   self:_ace_old__set_name_text(target, role)

   if radiant.entities.exists(target) then
      local custom_data = radiant.entities.get_custom_data(target)
      self._sv._parent:add_i18n_data(role .. '_custom_data', custom_data)
   end
end

return AceAnimalCompanionScript
