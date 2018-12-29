local TrapperClass = require 'stonehearth.jobs.trapper.trapper'
local AceTrapperClass = class()

AceTrapperClass._old_should_tame = TrapperClass.should_tame
function AceTrapperClass:should_tame(target)
   local trappable = radiant.entities.get_component_data('stonehearth:trapper:trapping_grounds', 'stonehearth:trapping_grounds').trappable_animal_weights
   local big_game = trappable and trappable.big_game or {}
   local is_big_game = big_game[target:get_uri()]
   if not is_big_game then
      return self:_old_should_tame(target)
   else
      return false
   end
end

return AceTrapperClass
