local PresenceRenderer = require 'stonehearth.renderers.presence.presence_renderer'
local AcePresenceRenderer = class()

AcePresenceRenderer._ace_old__update_cursor_for_player = PresenceRenderer._update_cursor_for_player
function AcePresenceRenderer:_update_cursor_for_player(player_id, presence_data)
   local data = self._datastore:get_data()
   if data.limit_data then
      -- destroy any existing cursor spheres (since they'll be in outdated locations)
      if self._players then
         for player_id, player_data in pairs(self._players) do
            if player_data.cursor_sphere ~= nil then
               player_data.cursor_sphere:destroy()
               player_data.cursor_sphere = nil
            end
            -- if player_data.cursor_node then
            --    player_data.cursor_node:destroy()
            --    player_data.cursor_node = nil
            -- end
         end
      end
   else
      self:_ace_old__update_cursor_for_player(player_id, presence_data)
   end
end

return AcePresenceRenderer
