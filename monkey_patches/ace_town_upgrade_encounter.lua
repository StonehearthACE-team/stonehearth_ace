local TownUpgradeEncounter = require 'stonehearth.services.server.game_master.controllers.encounters.town_upgrade_encounter'
local AceTownUpgradeEncounter = class()

local STAGE = {
   NOT_STARTED = 'NOT_STARTED',

   WAIT_FOR_FACILITY_IN_WORLD = 'WAIT_FOR_FACILITY_IN_WORLD',
   SETUP = 'SETUP',
   CONGREGATING = 'CONGREGATING',
   UPGRADE_VFX = 'UPGRADE_VFX',
   CELEBRATING = 'CELEBRATING',
   WRAPUP = 'WRAPUP',

   FINISHED = 'FINISHED',
}

local RESOURCE_TO_RESTORE = {
   calories = 'max',
   sleepiness = 'min',
   social_satisfaction = 'max',
}

function AceTownUpgradeEncounter:stage_1_setup()
   self._sv.stage = STAGE.SETUP
   self.__saved_variables:mark_changed()

   -- Make sure the facility can't be moved.
   self._sv.old_facility:get_component('stonehearth:commands'):set_command_enabled('stonehearth:commands:move_item', false)

   -- Start music.
   self:_start_music()

   -- Reset needs.
   local population = stonehearth.population:get_population(self._sv.ctx.player_id)
   for _, citizen in population:get_citizens():each() do
      for resource_name, target in pairs(RESOURCE_TO_RESTORE) do
         local resources = citizen:get_component('stonehearth:expendable_resources')
         local value
         if target == 'max' then
            value = resources:get_max_value(resource_name)
         elseif target == 'min' then
            value = resources:get_min_value(resource_name)
         else
            assert(false, 'Invalid resource target: ' .. target .. '; must be "min" or "max".')
         end
         resources:set_value(resource_name, value)
      end
   end

   -- Seed conversation subjects.
   if self._sv._info.conversation_subjects then
      local population = stonehearth.population:get_population(self._sv.ctx.player_id)
      for _, citizen in population:get_citizens():each() do
         for _, subject_uri in ipairs(self._sv._info.conversation_subjects) do
            local subjects = citizen:get_component('stonehearth:subject_matter')
            subjects:add_subject(subject_uri)
            subjects:add_override({
               subject = subject_uri,
               sentiment = 1
            })
         end
      end
   end

   -- Grant thought.
   if self._sv._info.thought then
      local population = stonehearth.population:get_population(self._sv.ctx.player_id)
      for _, citizen in population:get_citizens():each() do
         radiant.entities.add_thought(citizen, self._sv._info.thought)
      end
   end

   -- Update the tier in the old system, which is still used to drive unlocked music, templates, etc.
   local tier_achieved = self._sv._info.tier_achieved
   if tier_achieved then
      local population = stonehearth.population:get_population(self._sv.ctx.player_id)
      population:set_city_tier(tier_achieved)
   end

   -- Create announcement bulletin instead of succeeding at once.
   if self._sv._info.dialog then
      local dialog_info = self._sv._info.dialog
      self._sv.bulletin_data = radiant.shallow_copy(self._sv._info.dialog)
      self._sv.bulletin_data.ok_callback = '_on_bulletin_acknowledged'
      self._sv.bulletin = stonehearth.bulletin_board:post_bulletin(self._sv.ctx.player_id)
                                    :set_ui_view('StonehearthCityTierAchievedBulletin')
                                    :set_callback_instance(self)
                                    :set_type(self._sv._info.bulletin_type or 'town_lvlup')
                                    :set_sticky(true)
                                    :set_keep_open(true)
                                    :set_close_on_handle(false)
                                    :set_data(self._sv.bulletin_data)
                                    :add_i18n_data('town_name', stonehearth.town:get_town(self._sv.ctx.player_id):get_town_name())
      self.__saved_variables:mark_changed()
   end

   -- Grant bonus + bulletins about unlocks if any
   if self._sv._info.town_bonus then
      local town = stonehearth.town:get_town(self._sv.ctx.player_id)
      town:add_town_bonus(self._sv._info.town_bonus)
   end

   self:stage_2_congregate()
end

AceTownUpgradeEncounter._ace_old_stage_4_celebrate = TownUpgradeEncounter.stage_4_celebrate
function AceTownUpgradeEncounter:stage_4_celebrate()
   self:_ace_old_stage_4_celebrate()

   if radiant.entities.exists(self._sv.old_facility) then
      local commands = self._sv.old_facility:get_component('stonehearth:commands')
      if commands then
         commands:set_command_enabled('stonehearth:commands:move_item', true)
      end
   end
end

function AceTownUpgradeEncounter:_start_music()
   local track = self._sv._info.custom_music or 'celebration'
   radiant.events.trigger(radiant, 'stonehearth:request_music_track', { player_id = self._sv.ctx.player_id, track = track })
end

return AceTownUpgradeEncounter
