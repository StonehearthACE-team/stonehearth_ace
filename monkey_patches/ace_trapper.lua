local TrapperClass = require 'stonehearth.jobs.trapper.trapper'
local BaseJob = require 'stonehearth.jobs.base_job'
local AceTrapperClass = class()
local log = radiant.log.create_logger('trapper')

function AceTrapperClass:is_trapper()
   return true
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

function AceTrapperClass:_on_clear_trap(args)
   local base_exp
   if args.trapped_entity_id then
      base_exp = self._xp_rewards['successful_trap']
   else
      base_exp = self._xp_rewards['unsuccessful_trap']
   end

   self._job_component:add_exp(base_exp * args.experience_multiplier)
end

return AceTrapperClass
