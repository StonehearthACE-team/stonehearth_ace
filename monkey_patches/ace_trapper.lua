local TrapperClass = require 'stonehearth.jobs.trapper.trapper'
local BaseJob = require 'stonehearth.jobs.base_job'
local AceTrapperClass = class()
local log = radiant.log.create_logger('trapper')

AceTrapperClass._ace_old_initialize = TrapperClass.initialize
function AceTrapperClass:initialize()
	self:_ace_old_initialize()
   self._sv.max_num_animal_traps = {}
end

function AceTrapperClass:promote(json_path, options)
   BaseJob.promote(self, json_path, options)
   self._sv.max_num_siege_weapons = self._job_json.initial_num_siege_weapons or { trap = 0 }
	if next(self._sv.max_num_siege_weapons) then
      self:_register_with_town()
   end
	self._sv.max_num_animal_traps = self._job_json.initial_num_animal_traps or { fish_trap = 0 }
   if next(self._sv.max_num_animal_traps) then
      self:_register_with_town()
   end
   self.__saved_variables:mark_changed()
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

function AceTrapperClass:increase_max_placeable_traps(args)
	if args.max_num_siege_weapons then
		self._sv.max_num_siege_weapons = args.max_num_siege_weapons		
	end
	if args.max_num_animal_traps then
		self._sv.max_num_animal_traps = args.max_num_animal_traps
	end
   self:_register_with_town()
   self.__saved_variables:mark_changed()
end

AceTrapperClass._ace_old__register_with_town = TrapperClass._register_with_town
function AceTrapperClass:_register_with_town()
	self:_ace_old__register_with_town()
   local player_id = radiant.entities.get_player_id(self._sv._entity)
   local town = stonehearth.town:get_town(player_id)
   if town then
      town:add_placement_slot_entity(self._sv._entity, self._sv.max_num_animal_traps)
   end
end

return AceTrapperClass
