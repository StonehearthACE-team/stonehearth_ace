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

return AceCombatServerCommandsService
