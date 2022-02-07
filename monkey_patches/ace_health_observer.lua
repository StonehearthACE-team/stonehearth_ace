local HealthObserver = require 'stonehearth.ai.observers.health_observer'
local constants = require 'stonehearth.constants'

local AceHealthObserver = class()

local log = radiant.log.create_logger('health_observer')

AceHealthObserver._ace_old_activate = HealthObserver.activate
function AceHealthObserver:activate()
   self:_ace_old_activate()
   self._magically_healed_listener = radiant.events.listen(self._sv.entity, 'stonehearth_ace:entity:magically_healed', self, self._on_magically_healed)
end

AceHealthObserver._ace_old_destroy = HealthObserver.__user_destroy
function AceHealthObserver:destroy()
   self:_ace_old_destroy()

   if self._sv._recently_magically_treated_timer then
      self._sv._recently_magically_treated_timer:destroy()
      self._sv._recently_magically_treated_timer = nil
   end

   if self._magically_healed_listener then
      self._magically_healed_listener:destroy()
      self._magically_healed_listener = nil
   end
end

AceHealthObserver._ace_old__update = HealthObserver._update
function AceHealthObserver:_update(initial_update)
   self:_ace_old__update(initial_update)
   self:_check_update_wound_thoughts()
end

function AceHealthObserver:_check_update_thoughts(percentage, last_percentage)
   if percentage >= .99 then
      radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health:neutral')
   elseif percentage >= .9 then
      if not (last_percentage >= .9 and last_percentage < .99) then
         radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health:pain_minor')
      end
   elseif percentage >= .75 then
      if not (last_percentage >= .75 and last_percentage < .9) then
         radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health:pain_scratched')
      end
   elseif percentage >= .5 then
      if not (last_percentage >= .5 and last_percentage < .75) then
         radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health:pain_mild')
      end
   elseif percentage >= .25 then
      if not (last_percentage >= .25 and last_percentage < .5) then
         radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health:pain_moderate')
      end
   elseif not (last_percentage < .25) then
      radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health:pain_severe')
   end
end

function AceHealthObserver:_check_update_wound_thoughts()
   local highest_rank = 0
   for _, type in pairs(constants.health.WOUND_TYPES) do
      if self._sv.entity:get_component('stonehearth:buffs'):has_category_buffs(type) then
         local type_buffs = self._sv.entity:get_component('stonehearth:buffs'):get_buffs_by_category(type)
         for buff_id, buff in pairs(type_buffs) do
            local new_rank = buff:get_rank()
            if new_rank > highest_rank then
               highest_rank = new_rank
            end
         end
      end
   end
   
   if highest_rank > 1 then
      if highest_rank >= 4 then
         radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health_wounds:wound_extreme')
      elseif highest_rank == 3 then
         radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health_wounds:wound_high')
      elseif highest_rank == 2 then
         radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health_wounds:wound_medium')
      end
   else
      radiant.entities.add_thought(self._sv.entity, 'stonehearth:thoughts:health_wounds:no_wound')
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
