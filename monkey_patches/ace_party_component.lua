local Point3 = _radiant.csg.Point3

local PartyComponent = radiant.mods.require('stonehearth.components.party.party_component')
local AcePartyComponent = class()

local log = radiant.log.create_logger('party_component')

AcePartyComponent._ace_old_destroy = PartyComponent.__user_destroy
function AcePartyComponent:destroy()
   for _, timer in pairs(self._stop_patrolling_timers) do
      timer:destroy()
   end
   self._stop_patrolling_timers = nil

   self:_ace_old_destroy()
end

AcePartyComponent._ace_old__initialize_party = PartyComponent._initialize_party
function AcePartyComponent:_initialize_party()
   self._registered_patrollers = {}
   self._next_position_to_fill = {}
   self._stop_patrolling_timers = {}
   self._max_patrollers = stonehearth.constants.patrolling.MAX_PATROLLERS_PER_PARTY
   
   self:_ace_old__initialize_party()
   self:_update_manage_party_command()
end

function AcePartyComponent:_update_manage_party_command()
   local party = self._sv.banner_variant
   if party then
      local command = 'stonehearth_ace:commands:manage_' .. party
      local command_component = self._entity:add_component('stonehearth:commands')
      command_component:add_command(command)
      command_component:set_command_event_data(command, {party = party})
   end
end

AcePartyComponent._ace_old_set_banner_variant = PartyComponent.set_banner_variant
function AcePartyComponent:set_banner_variant(variant)
   self:_ace_old_set_banner_variant(variant)
   self:_update_manage_party_command()
end

AcePartyComponent._ace_old_remove_member = PartyComponent.remove_member
function AcePartyComponent:remove_member(id)
   self:unregister_patroller(id)
   self:_ace_old_remove_member(id)
end

AcePartyComponent._ace_old_try_set_patrol_lead = PartyComponent.try_set_patrol_lead
function AcePartyComponent:try_set_patrol_lead(new_leader)
   local result = self:_ace_old_try_set_patrol_lead(new_leader)
   if result and new_leader then
      self:register_patroller(new_leader)
   end

   return result
end

function AcePartyComponent:can_register_patroller(patroller)
   local count = #self._registered_patrollers

   local id = patroller and patroller:get_id()
   for _, patroller_id in ipairs(self._registered_patrollers) do
      if patroller_id == id then
         -- if they're already registered and there's no stop patrolling timer for them, assume it's okay
         if not self._stop_patrolling_timers[id] then
            return true
         else
            -- otherwise, reduce the count by one to account for them being in it
            count = count - 1
            break
         end
      end
   end

   return count < self._max_patrollers
end

function AcePartyComponent:register_patroller(new_patroller)
   local id = new_patroller:get_id()
   if self._stop_patrolling_timers[id] then
      self._stop_patrolling_timers[id]:destroy()
      self._stop_patrolling_timers[id] = nil
   end

   --log:debug('trying to register patroller %s; current patrollers: %s', id, radiant.util.table_tostring(self._registered_patrollers))

   for _, patroller_id in ipairs(self._registered_patrollers) do
      if patroller_id == id then
         return
      end
   end

   log:debug('inserting patroller %s; current patrollers: %s', id, radiant.util.table_tostring(self._registered_patrollers))

   local index = table.remove(self._next_position_to_fill) or (#self._registered_patrollers + 1)
   table.insert(self._registered_patrollers, index, id)
   radiant.events.trigger_async(self._entity, 'stonehearth_ace:patroller_registered')
end

-- give a grace period before unregistering a patroller in case a patrol point is reached and they want to continue patrolling
function AcePartyComponent:stop_patrolling(id)
   if self._stop_patrolling_timers[id] then
      return
   end

   self._stop_patrolling_timers[id] = stonehearth.calendar:set_timer('entity stopped patrolling, unregister', '5m', function()
         self:unregister_patroller(id)
      end)
end

function AcePartyComponent:unregister_patroller(id)
   if self._stop_patrolling_timers[id] then
      self._stop_patrolling_timers[id]:destroy()
      self._stop_patrolling_timers[id] = nil
   end

   for index, patroller_id in ipairs(self._registered_patrollers) do
      if patroller_id == id then
         table.remove(self._registered_patrollers, index)
         if #self._registered_patrollers < 1 then
            self._next_position_to_fill = {}
         else
            table.insert(self._next_position_to_fill, index)
         end
         radiant.events.trigger_async(self._entity, 'stonehearth_ace:patroller_unregistered')
         break
      end
   end
end

function AcePartyComponent:get_formation_offset(member)
   local patrol_lead = self:get_patrol_lead()

   -- patrol leads are always at the center of the formation
   if member == patrol_lead then
      return Point3.zero
   end

   local member_id = member:get_id()
   local formation_size = self._sv.party_size
   local formation_width = math.ceil(math.sqrt(formation_size))

   -- c is the zero-based row/col closest to the center of the formation
   local c = math.floor((formation_width - 1) * 0.5)
   local leader_index = c * formation_width + c

   local patrol_lead_id = patrol_lead and patrol_lead:is_valid() and patrol_lead:get_id()
   local member_index = 0

   -- ACE: first go through registered patrollers and give a position based on that index
   local checked = {}
   local found = false
   for _, patroller_id in ipairs(self._registered_patrollers) do
      if patroller_id == member_id then
         found = true
         break
      elseif patroller_id ~= patrol_lead_id then
         member_index = member_index + 1
      end
      checked[patroller_id] = true
   end

   if not found then
      for other_id, _ in pairs(self._sv.members) do
         if other_id == member_id then
            break
         end
         -- skip patrol lead when advancing the index
         -- ACE: also skip members we already checked
         if other_id ~= patrol_lead_id and not checked[other_id] then
            member_index = member_index + 1
         end
      end
   end

   -- reserve the leader index for the patrol lead
   if member_index >= leader_index then
      member_index = member_index + 1
   end

   -- a is the zero based column index
   local a = member_index % formation_width
   -- b is the zero based row index
   local b = math.floor(member_index / formation_width)

   -- calculate the offset centered about (c, 0, c)
   local spacing = stonehearth.constants.patrolling.SPACING
   local x = (a - c) * spacing
   local z = (b - c) * spacing
   local offset = Point3(x, 0, z)
   return offset
end

return AcePartyComponent
