local CombatServerCommandsService = require 'stonehearth.services.server.combat_server_commands.combat_server_commands_service'
local AceCombatServerCommandsService = class()

function AceCombatServerCommandsService:cancel_order_on_target(player_id, target)
   local get_work_player_id = radiant.entities.get_work_player_id

   for id, command in pairs(self._sv.individual_commands) do
      if get_work_player_id(command.entity) == player_id and command.target == target then
         self:_cancel_order_on_entity(command.entity)
      end
   end

   local pop = stonehearth.population:get_population(player_id)
   local parties = pop and pop:get_parties()
   if parties then
      for name, party in pairs(parties) do
         if get_work_player_id(party) == player_id then
            local party_marker = self._sv.party_markers[party:get_id()]
            if party_marker and party_marker.ghost == target then
               self:_cancel_order_on_party(party)
            end
         end
      end
   end
end

AceCombatServerCommandsService._ace_old__issue_individual_party_command = CombatServerCommandsService._issue_individual_party_command
function AceCombatServerCommandsService:_issue_individual_party_command(member, party, party_component, target_info, event_type)
   -- if the player has the gameplay setting disabled, check if this member's job is enabled in order to apply the party command
   local issue_command = self:_should_issue_individual_party_command_when_job_disabled(member)
   if not issue_command then
      local work_order_component = member:get_component('stonehearth:work_order')
      issue_command = work_order_component and work_order_component:is_work_order_enabled('job')
   end

   if issue_command then
      self:_ace_old__issue_individual_party_command(member, party, party_component, target_info, event_type)
   end
end

function AceCombatServerCommandsService:reconsider_all_individual_party_commands(party)
   local party_component = party:get_component('stonehearth:party')
   for id, member in party_component:each_member() do
      self:reconsider_individual_party_commands(member, self:_is_job_enabled(member), true)
   end
end

function AceCombatServerCommandsService:reconsider_individual_party_commands(member, job_enabled, gameplay_setting_changed)
   local party_member_comp = member:get_component('stonehearth:party_member')
   local party = party_member_comp and party_member_comp:get_party()
   if party then
      -- we only need to apply/remove party commands if the gameplay setting is disabled or if it just changed
      if gameplay_setting_changed or not self:_should_issue_individual_party_command_when_job_disabled(member) then
         if job_enabled then
            self:apply_party_commands_to_entity(party, member)
         else
            self:remove_party_commands_from_entity(party, member:get_id())
         end
      end
   end
end

function AceCombatServerCommandsService:_is_job_enabled(member)
   local work_order_component = member:get_component('stonehearth:work_order')
   return work_order_component and work_order_component:is_work_order_enabled('job')
end

function AceCombatServerCommandsService:_should_issue_individual_party_command_when_job_disabled(player_id)
   if not radiant.util.is_string(player_id) then
      player_id = radiant.entities.get_player_id(player_id)
   end
   return stonehearth.client_state:get_client_gameplay_setting(player_id, 'stonehearth_ace', 'issue_party_commands_when_job_disabled', true)
end

return AceCombatServerCommandsService
