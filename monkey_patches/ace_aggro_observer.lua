local constants = require 'stonehearth.constants'

local AggroObserver = require 'stonehearth.ai.observers.aggro_observer'
local AceAggroObserver = class()

local log = radiant.log.create_logger('aggro_observer')

AceAggroObserver._ace_old__is_killable = AggroObserver._is_killable
function AceAggroObserver:_is_killable(target)
   local killable = self:_ace_old__is_killable(target)
   
   -- also check to make sure it's not a training dummy
   if killable then
      if target:get_component('stonehearth_ace:training_dummy') then
         return false
      end
   end

   return killable
end

-- note that an entity is considered an ally of itself
function AceAggroObserver:_on_ally_battery(context)
   if not self:_is_killable(context.attacker) then
      return
   end

   -- we must be friendly with the target to care
   if not stonehearth.player:are_entities_friendly(context.target, self._sv._entity) then
      return
   end

   -- we must be hostile with the attacker to care
   if not stonehearth.player:are_entities_hostile(context.attacker, self._sv._entity) then
      return
   end

   local aggro = context.aggro_override or context.damage

   if context.target ~= self._sv._entity then
      -- aggro from allies getting hit is less than self getting hit
      aggro = aggro * constants.combat.ALLY_AGGRO_RATIO
   end

   self._target_table:modify_value(context.attacker, aggro)

   -- ACE: if we're currently attacking a siege object and the new target isn't a siege object
   -- reset the siege aggro
   -- don't do it for this entity; that's already being done when directly attacked
   if context.target == self._sv._entity then
      return
   end

   local primary_target = stonehearth.combat:get_primary_target(self._sv._entity)
   if not primary_target or primary_target == context.attacker then
      return
   end
   if radiant.entities.get_entity_data(primary_target, 'stonehearth:siege_object') then
      self:_reduce_siege_aggro_score(primary_target, constants.combat.ALLY_AGGRO_RATIO)
   end
end

-- when aggro score is inflated, reduce it by a percentage of its inflated amount
function AggroObserver:_reduce_siege_aggro_score(target, percentage)
   local value = radiant.entities.get_attribute(target, 'menace', 1)
   local cur_value = self._target_table:get_value(target) or value
   local new_value = math.max(value, math.floor((cur_value - value) * (1 - percentage) + value))
   log:debug('%s reducing siege object aggro of %s from %s to %s', self._sv._entity, target, cur_value, new_value)
   self._target_table:set_value(target, new_value)
end

return AceAggroObserver
