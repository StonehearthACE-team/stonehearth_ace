local AceFindHealableTargetObserver = class()

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

return AceFindHealableTargetObserver
