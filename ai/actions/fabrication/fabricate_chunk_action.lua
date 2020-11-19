local Entity = _radiant.om.Entity
local FabricateChunk = radiant.class()
FabricateChunk.name = 'fabricate chunk'
FabricateChunk.does = 'stonehearth:fabricate_chunk'
FabricateChunk.args = {
}

FabricateChunk.version = 2
FabricateChunk.priority = 1

local RETRY_TIMEOUT = 2500
local FAILSAFE_TIMEOUT = 5000

function FabricateChunk:start_thinking(ai, entity, args)
   self._revoked = false

   if not self._rejecting then
      self._found_chunks = {}
   end
   self._rejecting = false
   self._chunk = nil
   self._location = ai.CURRENT.location

   self._work_player_id = radiant.entities.get_work_player_id(entity)
   local key = string.format('fabricate_chunk for %s', self._work_player_id)
   self._filter_fn = stonehearth.ai:filter_from_key('stonehearth:fabricate_chunk', key, function(item)
         if item:get_uri() ~= 'stonehearth:build2:entities:chunk' then
            return false
         end

         return radiant.entities.get_player_id(item) == self._work_player_id
      end)

   self:_start_item_finder(ai, entity, args)
end

function FabricateChunk:_start_item_finder(ai, entity, args)

   local exhausted_cb = function()
      --printf('%s chunk finder exhausted', entity)
      if self._chunk_if == nil then
         return
      end

      self._chunk_if:destroy()
      self._chunk_if = nil
      self._found_chunks = {}

      -- We exhausted the universe.  But something might have become useful in the
      -- intervening time!  Loop around after waiting for a spell, and try again.
      self._retry_timer = radiant.set_realtime_timer('fabricate chunk retry', RETRY_TIMEOUT, function()
            --printf('retrying fab chunk finder')
            self:_start_item_finder(ai, entity, args)
         end)
   end

   local found_cb = function(chunk)
      if self._found_chunks[chunk:get_id()] then
         return false
      end
      --printf('%s found chunk %s', entity, chunk)
      self._found_chunks[chunk:get_id()] = true

      -- Wait, and then restart the search.  This probably only happens (mostly) when
      -- downstream thinking stalls (probably inside pickup_item, because its looking
      -- for a resource that no longer exists anywhere.)
      self._failsafe_timer = radiant.set_realtime_timer('fabricate chunk failsafe', FAILSAFE_TIMEOUT, function()
            --printf('%s failsafe timeout!', entity)
            ai:clear_think_output()
            ai:reject('fail safe timeout hit')
         end)

      local building = chunk:get_component('stonehearth:build2:chunk'):get_owning_building()

      ai:set_think_output({
         filter_fn = self._filter_fn,
         owner_player_id = self._work_player_id,
         description = 'fabricate chunks',
         action = self,
         chunk = chunk,
         building = building,
      })

      return true
   end

   if self._chunk_if then
      self._chunk_if:destroy()
   end
   --printf('%s fab chunk finder starting', entity)
   self._chunk_if = entity:add_component('stonehearth:item_finder'):find_reachable_entity_type(
         self._location,
         self._filter_fn,
         found_cb,
         {
            description = 'Finding chunk',
            owner_player_id = args.owner_player_id,
            exhausted_cb = exhausted_cb,
         })
end

function FabricateChunk:remember_permit(chunk, chunk_path_length, item_path_length, location)
   self._chunk = chunk
   self._total_length = chunk_path_length + item_path_length
   self._standing_location = location
end

function FabricateChunk:start(ai, entity, args)
   local acqd = self._chunk:get('stonehearth:build2:chunk'):acquire_work_permit(entity, self._total_length)
   if not acqd then
      ai:abort('could not acquire work permit')
      return
   end

   self._entity_id = entity:get_id()
   self._revoked_permit = radiant.events.listen(self._chunk, 'stonehearth:build2:permit_revoked', self, self._on_permit_revoked)
   self._reserved = self._chunk:get('stonehearth:build2:chunk'):reserve_chunk_adjacency(self._standing_location)
end

function FabricateChunk:stop_thinking(ai, entity, args)
   if self._chunk_if then
      self._chunk_if:destroy()
      self._chunk_if = nil
   end
   if self._retry_timer then
      self._retry_timer:destroy()
      self._retry_timer = nil
   end
   if self._failsafe_timer then
      self._failsafe_timer:destroy()
      self._failsafe_timer = nil
   end
end

function FabricateChunk:stop(ai, entity, args)
   if self._chunk and self._chunk:is_valid() then
      if self._revoked then
         self._chunk:get('stonehearth:build2:chunk'):revoke_work_permit(entity)
      else
         self._chunk:get('stonehearth:build2:chunk'):release_work_permit(entity)
      end

      if self._reserved then
         self._chunk:get('stonehearth:build2:chunk'):unreserve_chunk_adjacency(self._standing_location)
      end
   end

   if self._revoked_permit then
      self._revoked_permit:destroy()
      self._revoked_permit = nil
   end
   if self._retry_timer then
      self._retry_timer:destroy()
      self._retry_timer = nil
   end
   if self._failsafe_timer then
      self._failsafe_timer:destroy()
      self._failsafe_timer = nil
   end
end

function FabricateChunk:_on_permit_revoked(entity_id)
   -- We get revoke messages for everybody.
   if entity_id ~= self._entity_id then
      return
   end

   if self._started then
      self._revoked = true
      if self._revoked_permit then
         self._revoked_permit:destroy()
         self._revoked_permit = nil
      end
      self._ai:abort('permit revoked!')
   end
end

function FabricateChunk:on_reject(ai, entity, args)
   --printf('%s rejecting', entity)
   self._rejecting = true
end

local ai = stonehearth.ai
return ai:create_compound_action(FabricateChunk)
         :execute('stonehearth:abort_on_event_triggered', {
               source = ai.ENTITY,
               event_name = 'stonehearth:work_order:build:work_player_id_changed',
            })
         :execute('stonehearth:select_material_from_chunk', {
               chunk = ai.BACK(2).chunk,
            })
         :execute('stonehearth:material_to_filter_fn', {
               material = ai.PREV.material
            })
         :execute('stonehearth_ace:wait_for_building_material_banked', {
               building = ai.BACK(4).building,
               material = ai.BACK(2).material,
            })
         :execute('stonehearth:find_path_to_reachable_entity', {
               destination = ai.BACK(5).chunk
            })
         :execute('stonehearth:get_chunk_work_permit', {
               chunk_path_length = ai.PREV.path:get_path_length(),
               item_path_length = 0,
               chunk = ai.BACK(6).chunk,
               location = ai.PREV.path:get_finish_point(),
            })
         :execute('stonehearth:call_method_think', {
               obj = ai.BACK(7).action,
               method = 'remember_permit',
               args = {ai.BACK(7).chunk, ai.BACK(2).path:get_path_length(), 0, ai.BACK(2).path:get_finish_point()}
            })
         :execute('stonehearth:clear_carrying_now')
         :execute('stonehearth:follow_path', {
               path = ai.BACK(4).path,
            })
         :execute('stonehearth:fabricate_chunk_adjacent', {
               chunk = ai.BACK(10).chunk,
               block = ai.BACK(5).path:get_finish_point(),
               material = ai.BACK(8).material,
            })
