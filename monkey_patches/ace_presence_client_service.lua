local PresenceClientService = require 'stonehearth.services.client.presence_client.presence_client_service'
local AcePresenceClientService = class()

AcePresenceClientService._ace_old_destroy = PresenceClientService.__user_destroy
function AcePresenceClientService:destroy()
   self:_destroy_limited_data_call_timer(false)
   self:_ace_old_destroy()
end

function AcePresenceClientService:_destroy_limited_data_call_timer(ensure_normal_timer)
   if self._limited_data_call_timer then
      self._limited_data_call_timer:destroy()
      self._limited_data_call_timer = nil
   end

   if ensure_normal_timer and not self._call_timer then
      self:_start_call_timer()
   end
end

AcePresenceClientService._ace_old__check_presence_data_changed = PresenceClientService._check_presence_data_changed
function AcePresenceClientService:_check_presence_data_changed()
   local updated_presence_data = self._presence_datastore:get_data()
   local limit_data = updated_presence_data.limit_data
   -- backwards compatibility with previous true/false setting
   if limit_data == false or limit_data == 'unlimited' then
      -- no limits
      self:_destroy_limited_data_call_timer(true)
   elseif limit_data == 'very_limited' then
      -- no updates at all
      self:_destroy_call_timer()
      self:_destroy_limited_data_call_timer(false)
   else  -- if true or 'limited'
      -- make sure we're using our limited data timer
      self:_ensure_limited_data_call_timer()
   end

   self:_ace_old__check_presence_data_changed()
end

function PresenceClientService:_ensure_limited_data_call_timer()
   if self._limited_data_call_timer then
      return
   end

   self:_destroy_call_timer()

   self._limited_data_call_timer = radiant.set_realtime_interval('presence server update call', 500, function() -- slower frequency
         -- if self._modified.cursor_uri or self._modified.cursor_world_position then
         --    _radiant.call_obj('stonehearth.client_state', 'set_cursor_command', self._presence.cursor_uri, self._presence.cursor_world_position)
         --    self._modified.cursor_uri = false
         --    self._modified.cursor_world_position = false
         -- end

         if self._modified.region then
            _radiant.call_obj('stonehearth.client_state', 'set_xz_selection_command', self._presence.region, self._presence.region_type, self._presence.tool_type)
            self._modified.region = false
         end

         if self._modified.camera then
            _radiant.call_obj('stonehearth.client_state', 'set_camera_state_command', self._presence.camera_position, self._presence.camera_rotation)
            self._modified.camera = false
         end

         if self._modified.ghost then
            _radiant.call_obj('stonehearth.client_state', 'set_placement_ghost_command', self._presence.placement_ghost_uri, self._presence.placement_ghost_variant, self._presence.placement_ghost_position, self._presence.placement_ghost_rotation)
            self._modified.ghost = false
         end
      end)
end

return AcePresenceClientService
