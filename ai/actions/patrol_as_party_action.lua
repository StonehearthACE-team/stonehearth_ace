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
   
   local party = party_component._entity
   self._lease_listener = radiant.events.listen(party, 'stonehearth:party_leader_changed', function()
         self:_rethink(ai, entity, party_component)
      end)
   self._patrol_count_listener = radiant.events.listen(party, 'stonehearth_ace:patroller_unregistered', function()
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
      -- ACE: make sure we're allowed to patrol with the party
      if party_component:can_register_patroller(entity) then
         local register_abort_check = function()
            return not party_component:can_register_patroller(entity)
         end
         self:_destroy_listeners()
         ai:set_debug_progress('joining party lead by ' .. tostring(leader))
         ai:set_think_output({
               leader = leader,
               party = party_component._entity,
               register_abort_check = register_abort_check,
            })
      end
   else
      ai:set_debug_progress('cannot join party lead by ' .. tostring(leader or 'nil'))
   end
end

function PatrolAsParty:stop_thinking(ai, entity, args)
   self:_destroy_listeners()
end

function PatrolAsParty:_destroy_listeners()
   if self._lease_listener then
      self._lease_listener:destroy()
      self._lease_listener = nil
   end
   if self._patrol_count_listener then
      self._patrol_count_listener:destroy()
      self._patrol_count_listener = nil
   end
end

function PatrolAsParty:start(ai, entity, args)
   local party_component = radiant.entities.get_party_component(entity)
   if party_component then
      if not party_component:can_register_patroller(entity) then
         ai:abort('can no longer register patroller!')
         return
      end
      party_component:register_patroller(entity)
   end
end

function PatrolAsParty:stop(ai, entity, args)
   local party_component = radiant.entities.get_party_component(entity)
   if party_component then
      party_component:stop_patrolling(entity:get_id())
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
            event_name = 'stonehearth:party:party_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:training_enabled_changed',
            filter_fn = _should_abort
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.BACK(4).party,
            event_name = 'stonehearth_ace:patroller_registered',
            filter_fn = ai.BACK(4).register_abort_check
         })
         :execute('stonehearth:drop_carrying_now', {})
         :execute('stonehearth:set_posture', { posture = 'stonehearth:patrol' })
         :execute('stonehearth:walk_in_formation', { leader = ai.BACK(7).leader })
         :execute('stonehearth:log_patrol_time')
