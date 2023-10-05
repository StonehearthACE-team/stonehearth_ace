local Node = require 'stonehearth.services.server.game_master.controllers.node'
local Encounter = require 'stonehearth.services.server.game_master.controllers.encounter'
local AceEncounter = class()

local sound_constants = radiant.resources.load_json('stonehearth:data:sound_constants')

AceEncounter._ace_old_create = Encounter.create
function Encounter:create(json_path, game_master)
   self:_ace_old_create(json_path, game_master)
   self._sv.game_master:register_music(self, self:get_encounter_music())
end

function AceEncounter:destroy()
   if self._sv._info.encounter_music then
      self._sv.game_master:unregister_music(self)
   end
   if self._sv.script then
      if self._sv.script.destroy then
         self._sv.script:destroy()
      end
      self._sv.script = nil
      self.__saved_variables:mark_changed()
   end
   Node.__user_destroy(self)
end

function AceEncounter:get_encounter_music()
   if self._encounter_music == nil then
      -- load encounter music table
      local music = self._sv._info.encounter_music
      if not music then
         self._encounter_music = false
      else
         -- if music/ambient sound keys are present, try to load data from sound constants for them
         self._encounter_music = {
            music = music.music_sound_key and sound_constants.music[music.music_sound_key] or music.music,
            ambient = music.ambient_sound_key and sound_constants.ambient[music.ambient_sound_key] or music.ambient,
         }
      end
   end

   return self._encounter_music or nil
end

return AceEncounter
