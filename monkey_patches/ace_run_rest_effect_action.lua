local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'

local RunRestEffect = require 'stonehearth.ai.actions.health.run_rest_effect_action'
local AceRunRestEffect = radiant.class()

function AceRunRestEffect:run(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._bed = args.bed
   self._signaled = false

   self._health_listener = radiant.events.listen(entity, 'stonehearth:expendable_resource_changed:health', self, self._on_status_changed)
   self._conditions_listener = radiant.events.listen(entity, 'stonehearth:buff_removed', self, self._on_status_changed)
   self:_create_status_unchanged_timer()

   stonehearth.ai:reconsider_entity(self._bed, 'injured entity in bed')
   while not self._signaled do
      ai:execute('stonehearth:run_effect', { effect = 'rest_when_injured' })
   end
end

function AceRunRestEffect:_on_status_changed()
   if not self._signaled then
      local percentage = radiant.entities.get_health_percentage(self._entity)
      local conditions = healing_lib.get_conditions_needing_cure(self._entity)

      if percentage >= stonehearth.constants.health.STOP_RESTING_PERCENTAGE and not next(conditions) then
         self._signaled = true
         self:_destroy_status_unchanged_timer()
         -- This will wait for the effect to finish. Could abort instead, but if this action is
         -- used as a step in a compound action, this would break prevent following steps from running.
      else
         self:_create_status_unchanged_timer()
      end
   end
end

function AceRunRestEffect:_create_status_unchanged_timer()
   self:_destroy_status_unchanged_timer()
   local duration = stonehearth.constants.health.STOP_RESTING_STATUS_UNCHANGED_DURATION
   if duration then
      self._status_unchanged_timer = stonehearth.calendar:set_timer('stop resting if status unchanged', duration, function()
            self._signaled = true
         end)
   end
end

function AceRunRestEffect:_destroy_status_unchanged_timer()
   if self._status_unchanged_timer then
      self._status_unchanged_timer:destroy()
      self._status_unchanged_timer = nil
   end
end

AceRunRestEffect._ace_old_destroy = RunRestEffect.__user_destroy or RunRestEffect.destroy
function AceRunRestEffect:destroy()
   if self._conditions_listener then
      self._conditions_listener:destroy()
      self._conditions_listener = nil
   end
   self:_destroy_status_unchanged_timer()

   self:_ace_old_destroy()
end

return AceRunRestEffect
