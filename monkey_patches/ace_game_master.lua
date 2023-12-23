local GameMaster = require 'stonehearth.services.server.game_master.controllers.game_master'
local AceGameMaster = class()

AceGameMaster._ace_old_create = GameMaster.create
function AceGameMaster:create(player_id)
   self._encounter_music_map = {}
   self:_ace_old_create(player_id)
end

AceGameMaster._ace_old_restore = GameMaster.restore
function AceGameMaster:restore()
   -- if the encounter music is mapped the old way, unregister all of it
   -- individual encounters that have their own music will re-register themselves
   self._sv._encounter_music_map = nil
   self._sv._cur_music_encounter = nil
   self._sv._cur_music_encounter_id = nil

   -- we also need to clear out any saved encounter music (it's only getting saved to remote it to the client)
   self._sv.encounter_music = nil
   self.__saved_variables:mark_changed()

   self._encounter_music_map = {}
   self:_ace_old_restore()
end

function AceGameMaster:get_unique_encounter_id()
   self._sv._unique_encounter_id = (self._sv._unique_encounter_id or 0) + 1
   return self._sv._unique_encounter_id
end

function AceGameMaster:register_music(encounter_id, music)
   if music then
      if self._encounter_music_map[encounter_id] then
         return
      end

      self._encounter_music_map[encounter_id] = music
      if self:_is_encounter_music_higher_priority(self._sv.encounter_music, music) then
         self._sv.encounter_music = music
         self._cur_music_encounter_id = encounter_id
         self.__saved_variables:mark_changed()
      end
   end
end

function AceGameMaster:unregister_music(encounter_id)
   if self._encounter_music_map[encounter_id] then
      self._encounter_music_map[encounter_id] = nil
      if self._cur_music_encounter_id == encounter_id then
         self:_update_highest_priority_music()
      end
   end
end

function AceGameMaster:_is_encounter_music_higher_priority(cur_music, new_music)
   if new_music and new_music.combat and
         (not cur_music or not cur_music.combat) then
      return true
   end
   
   return new_music and new_music.music and
      (not cur_music or not cur_music.music or
         (new_music.music.priority or 0) > (cur_music.music.priority or 0))
end

function AceGameMaster:_update_highest_priority_music()
   -- go through the encounter music map and find the highest priority music
   local best_music, encounter_id
   for id, music in pairs(self._encounter_music_map) do
      if not best_music or self:_is_encounter_music_higher_priority(best_music, music) then
         best_music = music
         encounter_id = id
      end
   end

   self._sv.encounter_music = best_music
   self._cur_music_encounter_id = encounter_id

   self.__saved_variables:mark_changed()
end

return AceGameMaster
