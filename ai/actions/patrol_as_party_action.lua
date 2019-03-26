local PatrolAsParty = radiant.class()

PatrolAsParty.name = 'patrol as party'
PatrolAsParty.status_text_key = 'stonehearth:ai.actions.status_text.patrol'
PatrolAsParty.does = 'stonehearth:patrol'
PatrolAsParty.args = {}
PatrolAsParty.priority = 0.5

function PatrolAsParty:start_thinking(ai, entity, args)
   local party_component = radiant.entities.get_party_component(entity)
   if not party_component then
      ai:set_debug_progress('dead: not a party member')
      return
   end
   
   self._lease_listener = radiant.events.listen(party_component._entity, 'stonehearth:party_leader_changed', function()
         self:_rethink(ai, entity, party_component)
      end)
   self:_rethink(ai, entity, party_component)
end

function PatrolAsParty:_rethink(ai, entity, party_component)
   local leader = party_component:get_patrol_lead()
   if leader and leader ~= entity then
      if radiant.entities.get_work_player_id(leader) ~= radiant.entities.get_work_player_id(entity) then
         ai:set_debug_progress('not joining party lead; party leader not helping the same player')
         return
      end
      if self._lease_listener then
         self._lease_listener:destroy()
         self._lease_listener = nil
      end
      ai:set_debug_progress('joining party lead by ' .. tostring(leader))
      ai:set_think_output({
            leader = leader
         })
   else
      ai:set_debug_progress('cannot join party lead by ' .. tostring(leader or 'nil'))
   end
end

function PatrolAsParty:stop_thinking(ai, entity, args)
   if self._lease_listener then
      self._lease_listener:destroy()
      self._lease_listener = nil
   end
end

function _should_abort(source, training_enabled)
   return training_enabled
end

local ai = stonehearth.ai
return ai:create_compound_action(PatrolAsParty)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:training_enabled_changed',
            filter_fn = _should_abort
         })
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:set_posture', { posture = 'stonehearth:patrol' })
         :execute('stonehearth:walk_in_formation', { leader = ai.BACK(5).leader })
         :execute('stonehearth:log_patrol_time')
