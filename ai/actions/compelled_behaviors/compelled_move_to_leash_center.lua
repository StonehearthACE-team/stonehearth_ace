local Entity = _radiant.om.Entity

local CompelledMoveToLeashCenter = radiant.class()

CompelledMoveToLeashCenter.name = 'compelled move to leash center'
CompelledMoveToLeashCenter.does = 'stonehearth:compelled_behavior'
CompelledMoveToLeashCenter.args = {
   target = Entity
}
CompelledMoveToLeashCenter.priority = 1

function CompelledMoveToLeashCenter:start_thinking(ai, entity, args)
   self._ready = false
   self._is_thinking = true
   
   self._delay_start_timer = radiant.on_game_loop_once('CompelledMoveToLeashCenter start_thinking', function()
         self:_update_think_output(ai, entity, args)

         self._leash_changed_trace = radiant.events.listen(entity, 'stonehearth:combat_state:leash_changed', function()
               self:_update_think_output(ai, entity, args)
            end)
      end)
end

function CompelledMoveToLeashCenter:_update_think_output(ai, entity, args)
   if not self._is_thinking then
      return
   end

   local clear_think_output = function()
      if self._ready then
         ai:clear_think_output()
         self._ready = false
      end
   end

   local leash = stonehearth.combat:get_leash_data(entity)

   if leash and leash.center then
      local move_location = leash.center

      -- Clear think output if we have set it before
      clear_think_output()
      self._ready = true
      ai:set_think_output({ location = move_location })
   end
end

function CompelledMoveToLeashCenter:stop_thinking(ai, entity, args)
   self._is_thinking = false
   if self._delay_start_timer then
      self._delay_start_timer:destroy()
      self._delay_start_timer = nil
   end
   if self._leash_changed_trace then
      self._leash_changed_trace:destroy()
      self._leash_changed_trace = nil
   end
end

local ai = stonehearth.ai
return ai:create_compound_action(CompelledMoveToLeashCenter)
         :execute('stonehearth:goto_location', {
            reason = 'compelled move to leash center',
            location = ai.PREV.location,
         })
