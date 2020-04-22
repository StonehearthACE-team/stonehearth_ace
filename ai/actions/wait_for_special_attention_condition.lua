local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'
local WaitForSpecialAttentionCondition = radiant.class()

WaitForSpecialAttentionCondition.name = 'wait for special attention condition'
WaitForSpecialAttentionCondition.does = 'stonehearth_ace:wait_for_special_attention_condition'
WaitForSpecialAttentionCondition.args = {}
WaitForSpecialAttentionCondition.priority = {0, 1}

function WaitForSpecialAttentionCondition:start_thinking(ai, entity, args)
   self._ai = ai
   self._entity = entity
   self._signaled = false
   if not self._buff_listener then
      self._buff_listener = radiant.events.listen(entity, 'stonehearth:buff_added', self, self._on_buff_added)
   end
   self:_on_buff_added()  -- Safe to do sync since it can't call both clear_think_output and set_think_output.
end

function WaitForSpecialAttentionCondition:start(ai, entity, args)
   -- we have to destroy listener in start as well because start happens before stop thinking
   self:destroy()
end

function WaitForSpecialAttentionCondition:stop_thinking(ai, entity, args)
   self:destroy()
end

function WaitForSpecialAttentionCondition:destroy()
   if self._buff_listener then
      self._buff_listener:destroy()
      self._buff_listener = nil
   end
end

function WaitForSpecialAttentionCondition:_on_buff_added()
   local condition, priority = healing_lib.get_highest_priority_condition(self._entity)

   self._ai:set_utility(priority or 0)
   if priority ~= self._priority then
      self._priority = priority
      self:_signal()
   else
      self:_clear_signal()
   end
end

function WaitForSpecialAttentionCondition:_signal()
   if self._signaled then
      return
   end
   self._signaled = true
   self._ai:set_think_output()
end

function WaitForSpecialAttentionCondition:_clear_signal()
   if not self._signaled then
      return
   end

   self._ai:clear_think_output()
end

return WaitForSpecialAttentionCondition
