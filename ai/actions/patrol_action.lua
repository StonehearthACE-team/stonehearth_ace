local Patrol = radiant.class()

Patrol.name = 'patrol'
Patrol.status_text_key = 'stonehearth:ai.actions.status_text.patrol'
Patrol.does = 'stonehearth:patrol'
Patrol.args = {}
Patrol.priority = 0

function Patrol:start_thinking(ai, entity, args)
   local party_member_component = entity:get_component('stonehearth:party_member')
   self._party = party_member_component and party_member_component:get_party()
   
   if self._party then
      self._lease_listener = radiant.events.listen(self._party, 'stonehearth:party_leader_changed', function()
            self:_rethink(ai, entity)
         end)
      self:_rethink(ai, entity)
   else
      ai:set_think_output()
      ai:set_debug_progress('taking lead')
   end
end

function Patrol:_rethink(ai, entity)
   if self._party then
      local lease_component = self._party:add_component('stonehearth:lease')
      self._temp_lease = lease_component:acquire('stonehearth:patrol_lead_lease', entity, false, 1000)
      if not self._temp_lease then
         local leader = self._party:get_component('stonehearth:party'):get_patrol_lead()
         if leader then
            ai:set_debug_progress(string.format('waiting for patrol_lead_lease to be released (owner: %s)', tostring(leader) or 'nil'))
         else
            ai:reject('lease is being held temporarily; try again in a bit')
         end
         return
      end
   end
   
   if self._lease_listener then
      self._lease_listener:destroy()
      self._lease_listener = nil
   end
   ai:set_think_output()
   ai:set_debug_progress('taking the lead')
end

function Patrol:stop_thinking(ai, entity, args)
   if self._lease_listener then
      self._lease_listener:destroy()
      self._lease_listener = nil
   end
   if self._temp_lease then
      self._temp_lease:destroy()
      self._temp_lease = nil
   end
end

function Patrol:start(ai, entity, args)
   if radiant.entities.exists(self._party) then
      local party = self._party:get_component('stonehearth:party')
      if not party then
         ai:abort('lost party')
      end
      local success = party:try_set_patrol_lead(entity)
      if not success then
         ai:abort('could not obtain patrol_lead_lease')
      end
   end
   
   self._started = true
end

function Patrol:stop(ai, entity, args)
   if not self._started then
      return
   end

   if self._party then
      local party = self._party:get_component('stonehearth:party')
      if party then
         local success = party:try_set_patrol_lead(nil)
         radiant.verify(success, '%s could not release lease on %s', entity, self._party)
      end
   end
end

function _should_abort(source, training_enabled)
   return training_enabled
end

local ai = stonehearth.ai
return ai:create_compound_action(Patrol)
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth:work_order:job:work_player_id_changed',
         })
         :execute('stonehearth:abort_on_event_triggered', {
            source = ai.ENTITY,
            event_name = 'stonehearth_ace:training_enabled_changed',
            filter_fn = _should_abort
         })
         :execute('stonehearth:drop_backpack_contents_on_ground', {})
         :execute('stonehearth:set_posture', { posture = 'stonehearth:patrol' })
         :execute('stonehearth:add_buff', { buff = 'stonehearth:buffs:patrolling', target = ai.ENTITY})
         :execute('stonehearth:get_patrol_route')
         :execute('stonehearth:follow_path', { path = ai.PREV.path })
         :execute('stonehearth:log_patrol_time')
         :execute('stonehearth:patrol:idle')
