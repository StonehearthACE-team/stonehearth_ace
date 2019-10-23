local TrapperClass = require 'stonehearth.jobs.trapper.trapper'
local BaseJob = require 'stonehearth.jobs.base_job'
local AceTrapperClass = class()
local log = radiant.log.create_logger('trapper')

function TrapperClass:initialize()
   BaseJob.__user_initialize(self)
   self._sv._tame_beast_percent_chance = 0
   self._sv.max_num_siege_weapons = {}
end

AceTrapperClass._ace_old_should_tame = TrapperClass.should_tame
function AceTrapperClass:should_tame(target)
   local trappable = radiant.entities.get_component_data('stonehearth:trapper:trapping_grounds', 'stonehearth:trapping_grounds').trappable_animal_weights
   local big_game = trappable and trappable.big_game or {}
   local is_big_game = big_game[target:get_uri()]
   if not is_big_game then
      --log:debug('%s is not big game, so consider taming it', target)
      return self:_ace_old_should_tame(target)
   else
      --log:debug('%s IS big game, DON\'T consider taming it', target)
      return false
   end
end

return AceTrapperClass
