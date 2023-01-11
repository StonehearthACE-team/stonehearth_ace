local rng = _radiant.math.get_default_rng()

local AnimalCompanionScript = require 'stonehearth.data.traits.animal_companion.animal_companion_script'
local AceAnimalCompanionScript = class()

local log = radiant.log.create_logger('animal_companion_script')

AceAnimalCompanionScript._ace_old_create = AnimalCompanionScript.create
function AceAnimalCompanionScript:create(entity, uri, parent, args)
   self:_ace_old_create(entity, uri, parent, args)
   self._sv._args = args
end

function AceAnimalCompanionScript:_create_companion(player_id)
   log:debug('_create_companion for %s with args %s', self._sv._entity, radiant.util.table_tostring(self._sv._args))
   -- the args might specify a pet for us (e.g., from reembark)
   local args = self._sv._args
   local companion_id = args and args.pet_id_map and args.pet_id_map[args.pet_id]
   local companion = companion_id and radiant.entities.get_entity(companion_id)
   log:debug('trying to set companion to %s (%s)', tostring(companion), tostring(companion_id))
   if companion then
      self._sv._companion = companion
      self._sv._companion_id = companion_id
   else
      local i = rng:get_int(1, #self._possible_companions)

      local companion = radiant.entities.create_entity(self._possible_companions[i], { owner = player_id })
      self._sv._companion = companion

      self:_make_pet(player_id)
      self._sv._companion_id = self._sv._companion:get_id()
   end
end

function AceAnimalCompanionScript:_assign_roles()
   log:debug('_assign_roles for %s with args %s', self._sv._entity, radiant.util.table_tostring(self._sv._args))
   -- the args might specify whether the pet is the savior
   local args = self._sv._args
   local is_pet_savior = args and args.is_pet_savior
   if is_pet_savior == nil then
      is_pet_savior = rng:get_int(1, 2) == 1
   end

   if is_pet_savior then
      self._sv._savior = self._sv._companion
      self._sv._savee = self._sv._entity
   else
      self._sv._savior = self._sv._entity
      self._sv._savee = self._sv._companion
   end
end

AceAnimalCompanionScript._ace_old__set_name_text = AnimalCompanionScript._set_name_text
function AceAnimalCompanionScript:_set_name_text(target, role)
   self:_ace_old__set_name_text(target, role)

   if radiant.entities.exists(target) then
      local custom_data = radiant.entities.get_custom_data(target)
      self._sv._parent:add_i18n_data(role .. '_custom_data', custom_data)
   end
end

function AceAnimalCompanionScript:get_reembark_args(args)
   args.pet_id = self._sv._companion_id
   args.is_pet_savior = self._sv._savior == self._sv._companion

   return args
end

return AceAnimalCompanionScript
