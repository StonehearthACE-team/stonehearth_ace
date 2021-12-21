local AceWeatherRenderService = class()

function AceWeatherRenderService:_on_weather_changed()
   local weather_service_data = self._weather_service:get_data()
   local weather_state = weather_service_data.current_weather_state
   local weather_stamp = weather_service_data.current_weather_stamp

   if not weather_state or self._current_weather_stamp == weather_stamp then
      return
   end
   self._current_weather_stamp = weather_stamp

   -- Clean up any old data.
   if self._weather_type_renderer then
      self._weather_type_renderer:destroy()
      self._weather_type_renderer = nil
   end
   if self._camera_effect then
      local render_entity = _radiant.client.get_render_entity(self._camera_anchor)
      if render_entity then
         render_entity:stop_client_only_effect(self._camera_effect)
      end
      self._camera_effect = nil
   end
   if self._camera_effect_frame_trace then
      self._camera_effect_frame_trace:destroy()
      self._camera_effect_frame_trace = nil
   end
   
   -- Set up the new sky and lighting settings.
   local sky_settings = weather_state:get_data().sky_settings
   if sky_settings then
      stonehearth.sky_renderer:transition_sky(sky_settings, 2500)
   end
   
   -- If the weather type has its own renderer, spawn it.
   local renderer = weather_state:get_data().renderer
   if renderer then
      self._weather_type_renderer = radiant.create_controller(renderer, weather_state:get_data().script_controller)
      assert(self._weather_type_renderer)
   end

   -- Toggle clouds.
   _radiant.renderer.set_global_uniform('cloud_opacity', weather_state:get_data().hide_cloud_shadows and 0 or 1)

   -- If there's an on-camera effect, set it up.
   -- ACE - Also check if the player has a game setting disabling the weather effect from being rendered.
   local disable_weather_effect_rendering = stonehearth_ace.gameplay_settings:get_gameplay_setting('stonehearth_ace', 'disable_weather_effect_rendering')
   local camera_attached_effect = weather_state:get_data().camera_attached_effect
   if camera_attached_effect and disable_weather_effect_rendering ~= true then
      if not self._camera_anchor then
         self._camera_anchor = radiant.entities.create_entity('stonehearth:object:transient:unclipped', { debug_text = 'weather camera effect anchor' })
         radiant.terrain.place_entity_at_exact_location(self._camera_anchor, stonehearth.camera:get_position())
      end

      self._camera_effect_frame_trace = _radiant.client.trace_render_frame()
         :on_frame_start('update camera', function(now, alpha, frame_time, frame_time_wallclock)
            if not self._camera_effect then
               local render_entity = _radiant.client.get_render_entity(self._camera_anchor)
               if render_entity and render_entity:is_valid() then
                  self._camera_effect = render_entity:start_client_only_effect(camera_attached_effect)
               end
            end
            local camera_position = stonehearth.camera:get_position()
            camera_position = camera_position + stonehearth.camera:get_forward() * 50
            radiant.entities.move_to_absolute(self._camera_anchor, camera_position)
         end)
   end
end

return AceWeatherRenderService
