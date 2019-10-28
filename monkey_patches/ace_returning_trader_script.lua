local AceReturningTrader = class()

function AceReturningTrader:_accept_trade()
   --TODO: go through the reserved items and nuke them all
   self:_take_items()

   --Add the new items to the space near the banner
   local town = stonehearth.town:get_town(self._sv._player_id)
   local drop_origin = town:get_landing_location()
   if not drop_origin then
      return
   end

   --If the reward type was an object, make the new objects
   if self._sv._trade_info.rewards[self._sv._trade_data.reward_uri].type == 'object' then
      local uris = {}
      uris[self._sv._trade_data.reward_uri] = self._sv._trade_data.reward_count
      --TODO: attach a brief particle effect to the new stuff
      
      local town = stonehearth.town:get_town(self._sv._player_id)
      local default_storage = town and town:get_default_storage()
      radiant.entities.output_items(uris, drop_origin, 1, 3, { owner = self._sv._player_id }, nil, default_storage, true)
   end
end

return AceReturningTrader
