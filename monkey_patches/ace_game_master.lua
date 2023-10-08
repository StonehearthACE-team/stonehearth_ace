local GameMaster = require 'stonehearth.services.server.game_master.controllers.game_master'
local AceGameMaster = class()

function AceGameMaster:activate()
   if not self._sv._encounter_music_map then
      self._sv._encounter_music_map = {}
   end
end

function AceGameMaster:register_music(encounter, music)
   if music then
      for i, entry in ipairs(self._sv._encounter_music_map) do
         if entry.encounter == encounter then
            return
         end
      end

      -- TODO: we could maintain this as a sorted list by priority
      table.insert(self._sv._encounter_music_map, {
         music = music,
         encounter = encounter,
      })
      if self:_is_encounter_music_higher_priority(self._sv.encounter_music, music) then
         self._sv.encounter_music = music
         self._sv._cur_music_encounter = encounter
         self.__saved_variables:mark_changed()
      end
   end
end

function AceGameMaster:unregister_music(encounter)
   for i, entry in ipairs(self._sv._encounter_music_map) do
      if entry.encounter == encounter then
         self._sv._encounter_music_map[i] = nil
         local cur_music_encounter = self._sv._cur_music_encounter
         if cur_music_encounter == encounter then
            self:_update_highest_priority_music()
         end
         break
      end
   end
end

function AceGameMaster:_is_encounter_music_higher_priority(cur_music, new_music)
   if new_music.combat then
      return true
   end
   
   return new_music and new_music.music and
      (not cur_music or not cur_music.music or
         (new_music.music.priority or 0) > (cur_music.music.priority or 0))
end

function AceGameMaster:_update_highest_priority_music()
   -- go through the encounter music map and find the highest priority music
   local best_entry
   for _, entry in ipairs(self._sv._encounter_music_map) do
      if not best_entry or self:_is_encounter_music_higher_priority(best_entry.music, entry.music) then
         best_entry = entry
      end
   end

   self._sv.encounter_music = best_entry and best_entry.music
   self._sv._cur_music_encounter = best_entry and best_entry.encounter

   self.__saved_variables:mark_changed()
end

return AceGameMaster
