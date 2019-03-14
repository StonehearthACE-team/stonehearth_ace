local Buff = require 'stonehearth.components.buffs.buff'
local AceBuff = class()

local log = radiant.log.create_logger('buff')

-- "options" were already being passed in, but the parameter didn't exist and wasn't used
AceBuff._ace_old_create = Buff.create
function AceBuff:create(entity, uri, json, options)
   self:_ace_old_create(entity, uri, json)
   self._options = options
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

return AceBuff
