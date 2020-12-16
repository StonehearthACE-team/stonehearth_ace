local FindTargetObserver = require 'stonehearth.ai.observers.find_target_observer'
local AceFindTargetObserver = class()

AceFindTargetObserver._ace_old__subscribe_to_events = FindTargetObserver._subscribe_to_events
function AceFindTargetObserver:_subscribe_to_events()
   self._avoid_hunting_listener = radiant.events.listen(self._entity, 'stonehearth_ace:avoid_hunting_changed', self, self._reconsider_all_targets)
   self:_ace_old__subscribe_to_events()
end

AceFindTargetObserver._ace_old__unsubscribe_from_events = FindTargetObserver._unsubscribe_from_events
function AceFindTargetObserver:_unsubscribe_from_events()
   self:_ace_old__unsubscribe_from_events()
   if self._avoid_hunting_listener then
      self._avoid_hunting_listener:destroy()
      self._avoid_hunting_listener = nil
   end
end

function AceFindTargetObserver:_reconsider_all_targets()
   self:_update_all_target_scores()
   self:_check_for_target()
end

-- also take into consideration the whether the entity is set to avoid hunting
function AceFindTargetObserver:_update_highest_scored_target()
   local highest_scored_target = nil
   local is_hunting = false
   local job = self._entity:get_component('stonehearth:job')
   if job and job:has_role('hunter') then
      local properties_comp = self._entity:get_component('stonehearth:properties')
      is_hunting = not (properties_comp and properties_comp:has_property('avoid_hunting'))
   end
   local highest_score = is_hunting and 0 or stonehearth.constants.combat.MIN_MENACE_FOR_COMBAT

   for id, entry in pairs(self._scored_targets) do
      local target, score = entry.target, entry.score
      if score > highest_score and target:is_valid() then
         highest_score = score
         highest_scored_target = target
      end
   end

   self._highest_scored_target = highest_scored_target
   self._highest_score = highest_score
end

return AceFindTargetObserver
