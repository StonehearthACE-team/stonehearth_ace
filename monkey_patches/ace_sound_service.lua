local Sound = require 'stonehearth.services.client.sound.sound_service'
local AceSound = class()

AceSound._ace_old_destroy = Sound.__user_destroy
function AceSound:destroy()
   if self._gm_data_trace then
      self._gm_data_trace:destroy()
      self._gm_data_trace = nil
   end
   self:_ace_old_destroy()
end

--When the population changes, check the tier
function AceSound:_listen_on_population_changes(population_service, player_id)
   if not population_service then
      return
   end
   local my_player_id = player_id

   if not my_player_id then
      my_player_id = _radiant.client.get_player_id()
   end
   local populations = population_service:get_data().populations

   assert(populations, 'missing populations when starting sound service')
   local pop_faction = populations[my_player_id]
   if pop_faction then
      local pop_faction_data = pop_faction:get_data()
      self._player_city_tier = math.max(1, pop_faction_data.city_tier)
      self._player_acknowledges_tier_2 = pop_faction_data.player_acknowledges_tier_2
      self._player_acknowledges_tier_3 = pop_faction_data.player_acknowledges_tier_3

      self._kingdom = pop_faction_data.kingdom

      self._population_faction_trace = pop_faction:trace('sound service trace population faction')
         :on_changed(function(o)
            local pop_faction_data_change = pop_faction:get_data()

            --if the player has JUST acknowledged a pop faction change, then change the music
            if self._player_acknowledges_tier_2 ~= pop_faction_data_change.player_acknowledges_tier_2 or
               self._player_acknowledges_tier_3 ~= pop_faction_data_change.player_acknowledges_tier_3 then

               self._player_city_tier = pop_faction_data_change.city_tier

               self._player_acknowledges_tier_2 = pop_faction_data_change.player_acknowledges_tier_2
               self._player_acknowledges_tier_3 = pop_faction_data_change.player_acknowledges_tier_3
               self._trigger_tracklist_change = true

               --TODO: have a stinger? Or is the on-click OK music sufficient?
            end
         end)
   end
end

function AceSound:_on_threat_changed(data)
   self._log:info('threat level is now %.2f', data.threat_level)
   self._is_in_combat = data.in_combat
   self._threat_level = data.threat_level
   self:recommend_combat_music(self._combat_music_override)
end

-- overriding for debug messages
function AceSound:recommend_game_music(requestor, channel, info)
   if channel ~= 'ambient' then
      self._log:error('recommend_game_music: %s %s %s', requestor, channel, info and radiant.util.table_tostring(info) or 'nil')
   end
   self:recommend_music(requestor, 'game_screen', channel, info)
end

function AceSound:recommend_combat_music(music)
   self._log:error('recommend_combat_music: %s; in_combat = %s, threat_level = %s, combat_started = %s',
         tostring(music), tostring(self._is_in_combat), tostring(self._threat_level), tostring(self._combat_started))
   self._combat_music_override = music
   
   if not music then
      local kingdom = self._kingdom
      if not kingdom then
         return
      end

      local music_data = self._constants.music.combat.kingdoms[kingdom] or self._constants.music.combat.kingdoms['stonehearth:kingdoms:ascendancy']
      music = music_data.combat_playlist
   end

   if self._is_in_combat and self._threat_level > 0 then
      self._combat_started = true
      self:recommend_game_music('combat', 'music', music)
      self:recommend_game_music('combat', 'ambient', self._constants.music.combat.ambient)
      return
   elseif self._combat_started and self._threat_level <= 0.1 then
      self._combat_started = false

      -- combat music is going... first fade it out by queueing a track
      -- with no music file.  when that's done, play the stinger and let
      -- the next music in the series fade in by recommending on combat
      -- music at all.
      self:recommend_game_music('combat', 'music', self._constants.music.combat.kill_combat_music)
      radiant.set_realtime_timer("Sound _on_threat_changed", self._constants.music.combat.kill_combat_music.fade_in, function()
            self:recommend_game_music('combat', 'music',   nil)
            self:recommend_game_music('combat', 'ambient', nil)
            self:_play_sound(self._constants.sounds.combat_finished_sound)
         end)
   end
end

AceSound._ace_old_on_server_ready = Sound.on_server_ready
function AceSound:on_server_ready()
   self:_ace_old_on_server_ready()
   _radiant.call_obj('stonehearth.game_master', 'get_root_node_command'):done(function(response)
         self._gm_data_trace = response.__self:trace('sound service trace gm data')
            :on_changed(function(o)
               local data = response.__self:get_data()
               if data.encounter_music then
                  if data.encounter_music.combat then
                     self:recommend_combat_music(data.encounter_music.combat)
                  end
                  if data.encounter_music.music then
                     self:recommend_game_music('encounter', 'music', data.encounter_music.music)
                  end
                  if data.encounter_music.ambient then
                     self:recommend_game_music('encounter', 'ambient', data.encounter_music.ambient)
                  end
               else
                  self:recommend_combat_music()
                  self:recommend_game_music('encounter', 'music', nil)
                  self:recommend_game_music('encounter', 'ambient', nil)
               end
            end)
         :push_object_state()
      end)

   self:set_soundtrack_override(stonehearth_ace.gameplay_settings:get_gameplay_setting('stonehearth_ace', 'soundtrack_override'))
end

function AceSound:set_soundtrack_override(override)
   local prev_override = self._soundtrack_override
   if not override or override == 'none' or not self._constants.music[override] then
      self._soundtrack_override = nil
   else
      self._soundtrack_override = override
   end

   if prev_override ~= self._soundtrack_override then
      self._trigger_tracklist_change = true
   end
end

function AceSound:_on_time_changed(date)
   local event_times = self._calendar_constants.event_times

   -- play sounds
   if date.hour == 0 then
      self._sunset_sound_played = false
      self._sunrise_sound_played = false
   end

   -- sounds
   if date.hour == event_times.sunrise_start and not self._sunrise_sound_played then
      self._sunrise_sound_played = true
      if not self:_in_combat() then
         self:_play_sound(self._rooster_set:choose_random())
         self:_play_sound(self._constants.sounds.daybreak_sound)
      end
   end
   if date.hour == event_times.sunset_end and not self._sunset_sound_played then
      self._sunset_sound_played = true
      if not self:_in_combat() then
         self:_play_sound(self._constants.sounds.owl_sound)
         self:_play_sound(self._constants.sounds.nightfall_sound)
      end
   end

   -- music
   local is_day = date.hour >= event_times.sunrise_end and date.hour < event_times.sunset_end
   local music_tracklist
   if not self._initial_music_tracklist then
      music_tracklist = self:_get_music_tracklist(is_day)
      if music_tracklist then 
         --self:recommend_game_music('clock', 'music',  music_tracklist)
         self._initial_music_tracklist = true
      end
   end

   if (date.hour == event_times.sunrise_start and not self._day_tracklist_created) or (self._trigger_tracklist_change and is_day) then
      self._day_tracklist_created = true
      self._night_tracklist_created = false
      self._trigger_tracklist_change = false
      music_tracklist = self:_get_music_tracklist(is_day)
   elseif (date.hour == event_times.sunset_end and not self._night_tracklist_created) or (self._trigger_tracklist_change and not is_day) then
      self._night_tracklist_created = true
      self._day_tracklist_created = false
      self._trigger_tracklist_change = false
      music_tracklist = self:_get_music_tracklist(is_day)
   end

   if music_tracklist then
      self:recommend_game_music('clock', 'music',  music_tracklist)
   end

   --TODO(lcai): revisit; do we really need to recommend music this frequently?
   --local tier_music = self:_choose_tier_music_track(is_day)
   --local weather_music = self:_choose_weather_music_track(is_day)
   --if weather_music and tier_music then
   --   local combined_music = radiant.deep_copy(tier_music)
   --   radiant.array_append(combined_music.track, weather_music.track)
   --   self:recommend_game_music('clock', 'music',  combined_music)
  -- elseif weather_music then
   --   self:recommend_game_music('clock', 'music',  weather_music)
   --elseif tier_music then
   --   self:recommend_game_music('clock', 'music', tier_music)
   --end

   local weather_state = self._weather_service and self._weather_service:get_data().current_weather_state 
   if weather_state and weather_state:get_data() then
      local ambient_sound_key = weather_state:get_data().ambient_sound_key
      if ambient_sound_key then
         if is_day then
            self:recommend_game_music('clock', 'ambient',  self._constants.ambient[ambient_sound_key].day)
         else
            self:recommend_game_music('clock', 'ambient',  self._constants.ambient[ambient_sound_key].night)
         end
      else
         self:recommend_game_music('clock', 'ambient', { '' }) 
      end
   else
      self:recommend_game_music('clock', 'ambient', { '' })
   end
end

function AceSound:_get_music_tracklist(is_day)
   local weather_music = self:_choose_weather_music_track(is_day)
   local music_tracklist = self._soundtrack_override and
         self:_choose_overriden_music_track(is_day, self._soundtrack_override) or
         self:_choose_tier_music_track(is_day)

   if not music_tracklist then
      return weather_music
   elseif weather_music then
      music_tracklist = radiant.deep_copy(music_tracklist)
      radiant.array_append(music_tracklist.track, weather_music.track)
   end

   return music_tracklist
end

function AceSound:_choose_overriden_music_track(is_day, soundtrack_override)
   local music_sound_key = soundtrack_override
   local music_data = self._constants.music[music_sound_key]
   radiant.assert(music_data, 'soundtrack override can not be found in music data', music_sound_key)

   local time_of_day = is_day and 'day' or 'night'
   -- Get map of playable songs for this time of day
   return music_data[time_of_day]
end

function AceSound:_choose_weather_music_track(is_day)
   local weather_state = self._weather_service and self._weather_service:get_data().current_weather_state   
   if not weather_state or not weather_state:get_data().music_sound_key then
      return -- don't recommend music if game hasn't be initialized yet or this weather has no soundtrack of its own
   end
   
   local music_sound_key = weather_state:get_data().music_sound_key
   local music_data = self._constants.music[music_sound_key]
   radiant.assert(music_data, 'weather music sound key %s does not exist in sound constants', music_sound_key)

   local time_of_day = is_day and 'day' or 'night'
   -- Get map of playable songs for this time of day
   local time_of_day_music = music_data[time_of_day]
   if not time_of_day_music then
      return
   end

   -- Get track for this time of day
   return time_of_day_music
end

return AceSound
