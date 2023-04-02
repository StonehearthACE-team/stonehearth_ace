local PresenceRenderer = require 'stonehearth.renderers.presence.presence_renderer'
local AcePresenceRenderer = class()

AcePresenceRenderer._ace_old__update_cursor_for_player = PresenceRenderer._update_cursor_for_player
function AcePresenceRenderer:_update_cursor_for_player(player_id, presence_data)
   local data = self._datastore:get_data()
   local limit_data = data.limit_data
   -- backwards compatible with previous true/false setting
   if limit_data ~= 'unlimited' and limit_data ~= false then
      -- destroy any existing cursor spheres (since they'll be in outdated locations)
      if self._players then
         for player_id, player_data in pairs(self._players) do
            if player_data.cursor_sphere ~= nil then
               player_data.cursor_sphere:destroy()
               player_data.cursor_sphere = nil
            end
            if player_data.cursor_node then
               player_data.cursor_node:destroy()
               player_data.cursor_node = nil
            end
         end
      end
   else
      self:_ace_old__update_cursor_for_player(player_id, presence_data)
   end
end

AcePresenceRenderer._ace_old__update_box_selection_for_player = PresenceRenderer._update_box_selection_for_player
function AcePresenceRenderer:_update_box_selection_for_player(player_id, presence_data)
   local data = self._datastore:get_data()
   local limit_data = data.limit_data
   if limit_data == 'very_limited' then
      -- destroy any existing box selection (since they'll be in outdated locations)
      if self._players then
         for player_id, player_data in pairs(self._players) do
            if player_data.box_selection_node then
               player_data.box_selection_node:destroy()
               player_data.box_selection_node = nil
            end
         end
      end
   else
      self:_ace_old__update_box_selection_for_player(player_id, presence_data)
   end
end

AcePresenceRenderer._ace_old__update_placement_ghost_for_player = PresenceRenderer._update_placement_ghost_for_player
function AcePresenceRenderer:_update_placement_ghost_for_player(player_id, presence_data)
   local data = self._datastore:get_data()
   local limit_data = data.limit_data
   if limit_data == 'very_limited' then
      -- destroy any existing box selection (since they'll be in outdated locations)
      if self._players then
         for player_id, player_data in pairs(self._players) do
            if player_data.ghost_entity then
               radiant.entities.destroy_entity(player_data.ghost_entity)
               player_data.ghost_entity = nil
               player_data.ghost_render_entity = nil
            end
         end
      end
   else
      self:_ace_old__update_placement_ghost_for_player(player_id, presence_data)
   end
end

return AcePresenceRenderer
