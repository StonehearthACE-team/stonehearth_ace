local HealthObserver = require 'stonehearth.ai.observers.health_observer'
local AceHealthObserver = class()

local log = radiant.log.create_logger('health_observer')

AceHealthObserver.__ace_old_activate = HealthObserver.activate
function AceHealthObserver:activate()
   self:__ace_old_activate()
   self._magically_healed_listener = radiant.events.listen(self._sv.entity, 'stonehearth_ace:entity:magically_healed', self, self._on_magically_healed)
end

AceHealthObserver.__ace_old_destroy = HealthObserver.__user_destroy
function AceHealthObserver:destroy()
   self:__ace_old_destroy()

   if self._sv._recently_magically_treated_timer then
      self._sv._recently_magically_treated_timer:destroy()
      self._sv._recently_magically_treated_timer = nil
   end

   if self._magically_healed_listener then
      self._magically_healed_listener:destroy()
      self._magically_healed_listener = nil
   end
end

-- ACE: patched to use buff timer instead of constant
function AceHealthObserver:_on_healed(e)
   local entity = self._sv.entity
   local buff = radiant.entities.add_buff(entity, 'stonehearth:buffs:recently_treated')
   local expire_time = buff:get_expire_time()

   stonehearth.ai:reconsider_entity(entity, 'recently_treated added', true)

   if self._sv._recently_treated_timer == nil and expire_time then
      local duration = expire_time - stonehearth.calendar:get_elapsed_time()
      self._sv._recently_treated_timer = stonehearth.calendar:set_persistent_timer('recently_treated_debuff', duration, radiant.bind(self, '_enable_treatment'))
   end
end

function AceHealthObserver:_on_magically_healed(e)
   local entity = self._sv.entity
   local buff = radiant.entities.add_buff(entity, 'stonehearth_ace:buffs:recently_magically_treated')
   local expire_time = buff:get_expire_time()

   stonehearth.ai:reconsider_entity(entity, 'recently_treated added', true)

   if self._sv._recently_magically_treated_timer == nil and expire_time then
      local duration = expire_time - stonehearth.calendar:get_elapsed_time()
      self._sv._recently_magically_treated_timer = stonehearth.calendar:set_persistent_timer('recently_treated_debuff', duration, radiant.bind(self, '_enable_magical_treatment'))
   end
end

function AceHealthObserver:_enable_magical_treatment(e)
   local entity = self._sv.entity
   radiant.entities.remove_buff(entity, 'stonehearth_ace:buffs:recently_magically_treated')
   self._sv._recently_magically_treated_timer:destroy()
   self._sv._recently_magically_treated_timer = nil

   stonehearth.ai:reconsider_entity(entity, 'recently_treated removed', true)
end

return AceHealthObserver
