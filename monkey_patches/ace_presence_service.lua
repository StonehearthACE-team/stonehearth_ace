local AcePresenceService = class()

function AcePresenceService:is_multiplayer()
   local presence = self._sv._presence_entity:get_component('stonehearth:presence')
   return presence._sv.is_multiplayer
end

-- overriding to also update limit network data based on whether another player is connected
function AcePresenceService:set_connection_state(player_id, state)
   local presence = self._sv._presence_entity:get_component('stonehearth:presence')
   presence:update_presence_for_player(player_id, { connection_state = state })

   self._num_connected_players = presence:get_num_connected_players()
   self:_set_limit_network_data()
end

function AcePresenceService:set_limit_network_data(limit_data)
   self._sv._limit_network_data = limit_data
   self:_set_limit_network_data()
end

function AcePresenceService:_set_limit_network_data()
   -- if the setting hasn't been set yet, make sure it's set to the current gameplay setting
   if not self._sv._limit_network_data then
      self._sv._limit_network_data = radiant.util.get_global_config('mods.stonehearth_ace.limit_network_data', 'limited')
   end

   local limit_data = self._num_connected_players and self._num_connected_players > 1 and self._sv._limit_network_data or 'unlimited'
   local presence = self._sv._presence_entity:get_component('stonehearth:presence')
   presence:set_limit_network_data(limit_data)
end

return AcePresenceService
