local ChasePatrolParty = radiant.class()

ChasePatrolParty.name = 'chase patrol party'
ChasePatrolParty.status_text_key = 'stonehearth:ai.actions.status_text.patrol'
ChasePatrolParty.does = 'stonehearth:patrol'
ChasePatrolParty.args = {}
ChasePatrolParty.priority = 1.0

function ChasePatrolParty:start_thinking(ai, entity, args)
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

function ChasePatrolParty:_rethink(ai, entity, party_component)
   local leader = party_component:get_patrol_lead()
   if leader and leader ~= entity then
      if radiant.entities.get_work_player_id(leader) ~= radiant.entities.get_work_player_id(entity) then
         ai:set_debug_progress('not chasing party; party leader not helping the same player')
         return
      end

      -- ACE: make sure we're allowed to patrol with the party
      if party_component:can_register_patroller(entity) then
         local offset = party_component:get_formation_offset(entity)
         local stop_distance = offset:length()

         -- when close, let patrol as party take over
         if radiant.entities.distance_between(entity, leader) > stop_distance + 4 then
            local register_abort_check = function()
               return not party_component:can_register_patroller(entity)
            end
            self:_destroy_listeners()
            ai:set_debug_progress('chasing party lead by ' .. tostring(leader))
            ai:set_think_output({
                  leader = leader,
                  stop_distance = stop_distance,
                  party = party_component._entity,
                  register_abort_check = register_abort_check,
               })
         else
            ai:set_debug_progress('not chasing party; too close')
         end
      end
   else
      ai:set_debug_progress('cannot chase party lead by ' .. (tostring(leader) or 'nil'))
   end
end

function ChasePatrolParty:stop_thinking(ai, entity, args)
   self:_destroy_listeners()
end

function ChasePatrolParty:_destroy_listeners()
   if self._lease_listener then
      self._lease_listener:destroy()
      self._lease_listener = nil
   end
   if self._patrol_count_listener then
      self._patrol_count_listener:destroy()
      self._patrol_count_listener = nil
   end
end

function ChasePatrolParty:start(ai, entity, args)
   local party_component = radiant.entities.get_party_component(entity)
   if party_component then
      if not party_component:can_register_patroller(entity) then
         ai:abort('can no longer register patroller!')
         return
      end
      party_component:register_patroller(entity)
   end
end

function ChasePatrolParty:stop(ai, entity, args)
   local party_component = radiant.entities.get_party_component(entity)
   if party_component then
      party_component:stop_patrolling(entity:get_id())
   end
end

function _should_abort(source, training_enabled)
   return training_enabled
end

local ai = stonehearth.ai
return ai:create_compound_action(ChasePatrolParty)
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
         :execute('stonehearth:drop_carrying_now')
         :execute('stonehearth:chase_entity', {
            target = ai.BACK(6).leader,
            stop_distance = ai.BACK(6).stop_distance,
         })
