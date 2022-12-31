local constants = require 'stonehearth.constants'

local AggroObserver = require 'stonehearth.ai.observers.aggro_observer'
local AceAggroObserver = class()

local log = radiant.log.create_logger('aggro_observer')

AceAggroObserver._ace_old_post_activate = AggroObserver.post_activate
function AceAggroObserver:post_activate()
   self:_ace_old_post_activate()
   --self:_create_party_changed_listener()
end

AceAggroObserver._ace_old_destroy = AggroObserver.__user_destroy
function AceAggroObserver:destroy()
   self:_destroy_party_listeners()
   self:_ace_old_destroy()
end

function AceAggroObserver:_create_party_changed_listener()
   self._party_changed_listener = radiant.events.listen(self._sv._entity, 'stonehearth:party:party_changed', self, self._on_party_changed)
   self:_on_party_changed()
end

function AceAggroObserver:_destroy_party_listeners()
   self:_destroy_party_changed_listener()
   self:_destroy_party_target_acquired_listener()
end

function AceAggroObserver:_destroy_party_changed_listener()
   if self._party_changed_listener then
      self._party_changed_listener:destroy()
      self._party_changed_listener = nil
   end
end

function AceAggroObserver:_destroy_party_target_acquired_listener()
   if self._party_target_acquired_listener then
      self._party_target_acquired_listener:destroy()
      self._party_target_acquired_listener = nil
   end
end

function AceAggroObserver:_on_party_changed()
   self:_destroy_party_target_acquired_listener()
   local party = radiant.entities.get_party(self._sv._entity)

   if party then
      self._party_target_acquired_listener = radiant.events.listen(party, 'stonehearth:combat:target_acquired', self, self._on_party_target_acquired)
   end
end

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

-- When attacked, reset the (artifically high) aggro score of the inanimate siege object
-- you are attacking so you have a chance to attack your attacker
function AceAggroObserver:_on_party_target_acquired(context)
   -- only do this for party members that aren't this entity
   if context.attacker == self._sv._entity then
      return
   end

   local primary_target = stonehearth.combat:get_primary_target(self._sv._entity)
   if not primary_target then
      return
   end
   local is_siege = radiant.entities.get_entity_data(primary_target, 'stonehearth:siege_object')
   -- If assaulted by someone, reset the siege aggro score (may have been modified in attack siege action)
   -- so we have a chance to switch targets if attacker aggro score is higher
   if is_siege and primary_target ~= context.target then
      -- also make sure the party member's target is actually reachable and not a siege object
      if not stonehearth.combat:is_killable_target_of_type(context.target, 'siege') and _radiant.sim.topology.are_connected(self._sv._entity, context.target) then
         log:debug('%s resetting siege aggro on %s due to party target acquiring of %s', self._sv._entity, primary_target, context.target)
         self:_reset_siege_aggro_score(primary_target)
      end
   end
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
