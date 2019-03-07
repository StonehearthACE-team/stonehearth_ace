--[[
   this component interfaces between the statistics component, the unit_info component,
   and population_faction to apply titles to entities based on statistics
]]

local TitlesComponent = class()

function TitlesComponent:activate()
   self._stats_listener = radiant.events.listen(self._entity, 'stonehearth_ace:stat_changed', self, self._on_stat_changed)
end

function TitlesComponent:destroy()
   if self._stats_listener then
      self._stats_listener:destroy()
      self._stats_listener = nil
   end
end

function TitlesComponent:_on_stat_changed(args)
   local population = stonehearth.population:get_population(self._entity:get_player_id())
   if population then
      local titles = population:get_titles_for_statistic(self._entity, args)
      if titles then
         for title, rank in pairs(titles) do
            self:add_title(title, rank)
         end
      end
   end
end

function TitlesComponent:add_title(title, rank)
   if self._entity:add_component('stonehearth:unit_info'):add_title(title, rank) then
      -- alert the player that they gained a title
      local player_id = self._entity:get_player_id()
      local commands = self._entity:get_component('stonehearth:commands')
      local pop = stonehearth.population:get_population(player_id)

      local bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
         :set_ui_view('StonehearthAceAchievementAcquiredBulletinDialog')
         :set_callback_instance(self)
         :set_type('achievement')
         :set_data({
            title = 'i18n(stonehearth_ace:ui.game.bulletin.achievement_acquired_bulletin.new_title.title)',
            message = 'i18n(stonehearth_ace:ui.game.bulletin.achievement_acquired_bulletin.new_title.message)',
            zoom_to_entity = self._entity,
            has_character_sheet = commands and commands:has_command('stonehearth:commands:open_character_sheet')
         })
         :set_active_duration('1h')
         :add_i18n_data('entity', self._entity)
         :add_i18n_data('new_title', pop and pop:get_title_rank_data(self._entity, title, rank) or {})
   end
end

return TitlesComponent