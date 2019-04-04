local Buff = require 'stonehearth.components.buffs.buff'
local AceBuff = class()

local log = radiant.log.create_logger('buff')

local STAT_DURATION_UPDATE_INTERVAL = '25m+10m'  -- add variance so restored buffs don't all try to update their stats at the same time

-- "options" were already being passed in, but the parameter didn't exist and wasn't used
AceBuff._ace_old_create = Buff.create
function AceBuff:create(entity, uri, json, options)
   self:_ace_old_create(entity, uri, json)
   self._options = options
end

AceBuff._ace_old_destroy = Buff.destroy
function AceBuff:destroy()
   if self._duration_timer then
      self._duration_timer:destroy()
      self._duration_timer = nil
   end
   if self._json.duration_statistics_key then
      self:_update_duration_stat()
   end

   if self._ace_old_destroy then
      self:_ace_old_destroy()
   end
end

AceBuff._ace_old__create_buff = Buff._create_buff
function AceBuff:_create_buff()
   self:_ace_old__create_buff()

   -- now do any post-create options
   if self._options then
      if self._options.stacks and self._options.stacks > 1 then
         self._options.stacks = self._options.stacks - 1
         self:on_repeat_add(self._options)
      end
   end

   if self._json.duration_statistics_key and self._sv._entity:get_component('stonehearth_ace:statistics') then
      self:_create_duration_timer()
      self:_update_duration_stat()
   end
end

-- override to allow removing stacks instead of entire buff on expire
function Buff:_create_timer()
   local duration = self._default_duration
   if self._sv.expire_time then
      duration = self._sv.expire_time - stonehearth.calendar:get_elapsed_time()
      if self._timer then
         self._timer:destroy()
         self._timer = nil
      end
   end

   -- called when timer expires
   local destroy_fn
   destroy_fn = function()
      local stacks_to_remove = self._json.remove_stacks_on_expire
      if stacks_to_remove then
         self._sv.stacks = self._sv.stacks - (type(stacks_to_remove) == 'number' and stacks_to_remove or 1)
         if self._sv.stacks > 0 then
            -- TODO: add code for just removing a modifier rather than having to remove all and add all back in
            self:_destroy_modifiers()
            self:_restore_modifiers()

            self:_set_expiration_timer(duration, destroy_fn)
            return
         end
      end

      -- Set a flat so we'll know the buff is being destroyed because its timer expired
      self._removed_due_to_expiration = true
      self._sv.stacks = 0
      -- once we've expired, add cooldown buff
      if self._cooldown_buff then
         radiant.entities.add_buff(self._sv._entity, self._cooldown_buff)
      end
      self:destroy()
   end

   self:_set_expiration_timer(duration, destroy_fn)
end

function AceBuff:_set_expiration_timer(duration, destroy_fn)
   if duration then
      self._timer = stonehearth.calendar:set_timer('Buff removal timer', duration, destroy_fn)
      self._sv.expire_time = self._timer:get_expire_time()
      self.__saved_variables:mark_changed()
   end
end

function AceBuff:on_repeat_add(options)
   local repeat_add_action = self._json.repeat_add_action
   if repeat_add_action == 'renew_duration' then
      self:_destroy_timer()
      self:_create_timer()
      return true
   end

   if repeat_add_action == 'extend_duration' then
      -- assert(self._timer, string.format("Attempting to extend duration when buff %s doesn't have a duration", self._sv.uri))
      if self._sv.expire_time then
         self._sv.expire_time = self._sv.expire_time + self._default_duration
      end
      self:_create_timer()
      return true
   elseif repeat_add_action == 'stack_and_refresh' then
      -- if we've hit max stacks, refresh the timer duration but don't add a new stack
      for i = 1, options.stacks do
         self:_add_stack()
      end
      self:_destroy_timer()
      self:_create_timer()
      return true
   end

   if self._script_controller and self._script_controller.on_repeat_add then
      return self._script_controller:on_repeat_add(self._sv._entity, self, options)
   end

   return false
end

function AceBuff:_create_duration_timer()
   local interval = stonehearth.calendar:parse_duration(STAT_DURATION_UPDATE_INTERVAL)
   if not self._sv.expire_time or self._sv.expire_time - stonehearth.calendar:get_elapsed_time() > interval then
      self._duration_timer = stonehearth.calendar:set_interval('buff duration stat', interval, function()
         self:_update_duration_stat()
      end)
   end
end

function AceBuff:_update_duration_stat()
   local stats_comp = self._sv._entity:get_component('stonehearth_ace:statistics')
   if stats_comp then
      -- if we already have a prev_duration_time then add the difference
      -- otherwise, simply record the current time
      local prev_time = self._sv.prev_duration_time
      self._sv.prev_duration_time = stonehearth.calendar:get_elapsed_time()
      self.__saved_variables:mark_changed()

      if prev_time then
         stats_comp:increment_stat('buffs_duration', self._json.duration_statistics_key, math.max(0, self._sv.prev_duration_time - prev_time))
      end
   end
end

return AceBuff
