local Node = require 'stonehearth.services.server.game_master.controllers.node'
local Encounter = require 'stonehearth.services.server.game_master.controllers.encounter'
local AceEncounter = class()

local sound_constants = radiant.resources.load_json('stonehearth:data:sound_constants')

AceEncounter._ace_old_restore = Encounter.restore
function AceEncounter:restore()
   self:_ace_old_restore()
   self._is_restore = true
end

function AceEncounter:activate()
   self:load_json()

   -- if it's already been started, we need to register the music
   if self._is_restore then
      local ctx = self:_get_script_ctx()
      if ctx and ctx.parent_node then
         self._sv.game_master:register_music(self:get_unique_id(), self:get_encounter_music())
      end
   end
end

AceEncounter._ace_old_start = Encounter.start
function AceEncounter:start(ctx)
   -- this also assigns the unique id
   self._sv.game_master:register_music(self:get_unique_id(), self:get_encounter_music())
   return self:_ace_old_start(ctx)
end

function AceEncounter:destroy()
   if self._sv._info.encounter_music then
      self._sv.game_master:unregister_music(self:get_unique_id())
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

function AceEncounter:get_unique_id()
   if not self._sv.unique_id then
      self._sv.unique_id = self._sv.game_master:get_unique_encounter_id()
      self.__saved_variables:mark_changed()
      --self._log:debug('assigning unique id %s to encounter with datastore id %s', self._sv.unique_id, self.__saved_variables:get_id())
   end
   return self._sv.unique_id
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
            combat = music.combat_music_sound_key and radiant.util.get_nested_value(sound_constants.music, music.combat_music_sound_key) or music.combat_music,
            music = music.music_sound_key and radiant.util.get_nested_value(sound_constants.music, music.music_sound_key) or music.music,
            ambient = music.ambient_sound_key and radiant.util.get_nested_value(sound_constants.ambient, music.ambient_sound_key) or music.ambient,
         }
      end
   end

   return self._encounter_music or nil
end

return AceEncounter
