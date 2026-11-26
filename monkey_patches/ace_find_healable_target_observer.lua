local FindHealableTargetObserver = require 'stonehearth.ai.observers.find_healable_target_observer'
local constants = require 'stonehearth.constants'
local Point3 = _radiant.csg.Point3

local AceFindHealableTargetObserver = class()

local NOT_WITHIN_LEASH_PENALTY_MULTIPLIER = constants.combat.NOT_WITHIN_LEASH_PENALTY_MULTIPLIER

AceFindHealableTargetObserver._ace_old_activate = FindHealableTargetObserver.activate
function AceFindHealableTargetObserver:activate()
   self._medic_capabilities_changed_listener = radiant.events.listen(self._entity,
         'stonehearth_ace:medic_capabilities_changed', self, self._on_medic_capabilities_changed)
   
   self:_ace_old_activate()
end

function AceFindHealableTargetObserver:_on_medic_capabilities_changed(capabilities)
   self._medic_capabilities = capabilities
   self:_update_all_target_scores()
   self:_check_for_target()
end

-- just replaced radiant.entities.get_health_percentage with radiant.entities.get_effective_health_percentage (ACE)
function AceFindHealableTargetObserver:_get_target_score(target)
   -- the first time we see the target, we bump their heal score up by their percentage missing health
   local percentage = radiant.entities.get_effective_health_percentage(target)

   local heal_score = math.min(math.ceil((1-percentage) * 100))
   if heal_score < stonehearth.constants.combat.HEALING_IGNORE_TARGET_SCORE_THRESHOLD then
      return 0
   end

   local ic = target:get_component('stonehearth:incapacitation')
   if ic and (ic:is_incapacitated() or ic:is_rescued()) then
      return 0
   end

   return heal_score
end

-- target allowed to be nil
-- ACE: added non-combat heal option for when target (and self) aren't in combat
function AceFindHealableTargetObserver:_heal_target(target)
   self._log:info('setting target to %s', tostring(target))

   -- in order to not have to override a bunch of other functions that deal with self._task and self._current_target,
   -- only handle either combat or non-combat at a time; any combat target is prioritized over a non-combat target,
   -- and if there's an active non-combat task, it will be canceled if a combat target is found
   local target_in_combat = target and target:is_valid() and stonehearth.combat:is_in_combat(target)
   local current_target_in_combat = self._current_target and self._current_target:is_valid() and stonehearth.combat:is_in_combat(self._current_target)

   if self._task then
      if target == self._current_target then
         -- we're already healing that target, nothing to do
         assert(target == self._task:get_args().target)
         return
      elseif current_target_in_combat and not target_in_combat then
         -- we're currently healing a combat target, and we found a non-combat target, so ignore the new one
         return
      end
   end
   local current_target = stonehearth.combat:get_primary_target(self._entity)
   if current_target and current_target:is_valid() and not target then
      -- if we are trying to clear the primary target but the primary target is not friendly
      -- that target is set by the other target observer and we should leave it as is.
      -- TODO(yshan): consolidate the target observers.
      if stonehearth.player:are_entities_friendly(current_target, self._entity) then
         stonehearth.combat:set_primary_target(self._entity, target)
      end
   elseif current_target ~= target and (not target or target_in_combat) then
      stonehearth.combat:set_primary_target(self._entity, target)
   end

   if target ~= self._current_target then
      self:_destroy_task()
      self._current_target = target
   end

   if target and target:is_valid() then
      assert(not self._task)
      if target_in_combat then
         self._task = self._entity:add_component('stonehearth:ai')
                           :get_task_group('stonehearth:task_groups:solo:combat_unit_control')
                           :create_task('stonehearth:combat:heal_after_cooldown', { target = target })
      else
         self._task = stonehearth.town:get_town(self._entity)
                           :create_task_for_group('stonehearth:task_groups:healing',
                                                  'stonehearth:combat:heal_after_cooldown',
                                                  { target = target })
      end

      self._task:once()
         :notify_completed(
            function ()
               self._task = nil
               self:_check_for_target()
            end
         )
         :start()
   end
end

-- just replaced radiant.entities.get_health_percentage with radiant.entities.get_effective_health_percentage (ACE)
function AceFindHealableTargetObserver:_find_target()
   local stance = stonehearth.combat:get_stance(self._entity)
   local target, score

   if stance == 'passive' then
      -- don't attack
      self._log:info('stance is passive.  returning nil target.')
      return nil, nil
   end

   -- get the highest scored target
   target = self._highest_scored_target
   score = self._highest_score

   self._log:info('stance is %s.  returning %s as heal target.', stance, tostring(target))

   -- Can we get rid of this? We needed it because the healing observer updates the healing table
   -- asynchronously and may not have removed a newly friendly entity yet.
   if target ~= nil and target:is_valid() then
      if stonehearth.player:are_entities_friendly(target, self._entity) then
         local percentage = radiant.entities.get_effective_health_percentage(target)
         local guts_percentage = radiant.entities.get_resource_percentage(target, 'guts') or 1

         if percentage < 1 and guts_percentage >= 1 then
            -- Only return a score if you can heal the target (IE target health is < 100%)
            return target, score
         end
      end
   end

   return nil, nil
end

-- Adding nil checks and some safety for possible errors (ACE)
function AceFindHealableTargetObserver:_calculate_target_cost_benefit(entity_location, target, heal_score)
   if not target or not target:is_valid() then
      return 0
   end

   if not self._sight_sensor:contains_contents(target:get_id()) then
      local is_primary_target = target == self._combat_state:get_primary_target(self._entity)
      if not is_primary_target then
         return 0
      end
   end

   local target_location = nil
   local target_mob = target:get_component('mob')
   if target_mob then
      target_location = target_mob:get_world_grid_location()
   else
      return 0
   end

   if radiant.entities.is_entity_suspended(target) then
      return 0
   end

   local leash_penalty
   -- Inlining stonehearth.combat:get_distance_outside_leash() for perf.
   local leash = self._combat_state:get_leash_data()
   if leash and target_location then
      local projected_point = Point3(target_location)
      projected_point.y = leash.center.y
      local closest_point = leash.cube:get_closest_point(projected_point)
      leash_penalty = closest_point:distance_to(target_location) * NOT_WITHIN_LEASH_PENALTY_MULTIPLIER
   else
      leash_penalty = 0
   end
   local score = heal_score - leash_penalty
   if score < 0 then
      return 0
   end

   local distance
   if entity_location and target_location then
      distance = entity_location:distance_to(target_location)
   end
   if distance and distance < 8 then
      -- Below a minimum distance, being closer doesn't matter.
      -- How much does this matter for ranged healing?
      distance = 8
   end

   -- Only divide score by distance if we are not healing ourselves
   if distance and distance ~= 0 then
      score = score / distance
   end

   return score
end

return AceFindHealableTargetObserver
