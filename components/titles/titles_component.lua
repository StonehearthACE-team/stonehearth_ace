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
   local player_id = self._entity:get_player_id()
   local population = stonehearth.population:get_population(player_id)
   if population then
      local titles = population:get_titles_for_statistic(self._entity, args)
      if titles then
         for title, rank in pairs(titles) do
            if self._entity:add_component('stonehearth:unit_info'):add_title(title, rank) then
               -- TODO: alert the player that they gained a title
               -- local bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
               --    :set_ui_view('StonehearthLevelUpBulletinDialog')
               --    :set_callback_instance(self)
               --    :set_type('level_up')
               --    :set_data({
               --       title = title,
               --       char_name = name,
               --       zoom_to_entity = self._entity,
               --       has_class_perks = has_class_perks,
               --       class_perks = class_perk_descriptions,
               --       has_race_perks = has_race_perks,
               --       race_perks = race_perk_descriptions
               --    })
               --    :set_active_duration('1h')
               --    :add_i18n_data('entity_display_name', radiant.entities.get_display_name(self._entity))
               --    :add_i18n_data('entity_custom_name', radiant.entities.get_custom_name(self._entity))
               --    :add_i18n_data('job_name', job_name)
               --    :add_i18n_data('level_number', new_level)
            end
         end
      end
   end
end

return TitlesComponent