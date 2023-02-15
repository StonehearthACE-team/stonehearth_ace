--[[
   this component interfaces between the statistics component, the unit_info component,
   and population_faction to apply titles to entities based on statistics
]]

local TitlesComponent = class()

function TitlesComponent:initialize()
   self._sv.titles = {}
   self._sv.latest_title = nil
   self._sv.renown = 0
end

function TitlesComponent:restore()
   self._is_restore = true
end

function TitlesComponent:activate()
   self._stats_listener = radiant.events.listen(self._entity, 'stonehearth_ace:stat_changed', self, self._on_stat_changed)
   self._settings_listener = radiant.events.listen(radiant, 'title_selection_criteria_changed', self, self._select_new_title)
end

function TitlesComponent:post_activate()
   -- population hasn't been fully set up yet apparently in activate, so have to call this here
   self._player_id_trace = self._entity:trace_player_id('titles')
      :on_changed(
         function ()
            self:update_titles_json()
         end
      )

   self:update_titles_json()

   self._delay_listener_timer = radiant.on_game_loop_once('Titles Component creating listeners...', function()
      self:_create_trait_listeners()
   end)

   -- if they have titles but renown is 0, this is probably the first load after renown was added; calculate it
   if self._is_restore and next(self._sv.titles) and self._sv.renown == 0 then
      self:_recalculate_renown()
   end
end

function TitlesComponent:destroy()
   if self._delay_listener_timer then
      self._delay_listener_timer:destroy()
      self._delay_listener_timer = nil
   end

   if self._trait_added_listener then
      self._trait_added_listener:destroy()
      self._trait_added_listener = nil
   end

   if self._trait_removed_listener then
      self._trait_removed_listener:destroy()
      self._trait_removed_listener = nil
   end

   if self._stats_listener then
      self._stats_listener:destroy()
      self._stats_listener = nil
   end

   if self._settings_listener then
      self._settings_listener:destroy()
      self._settings_listener = nil
   end

   if self._player_id_trace then
      self._player_id_trace:destroy()
      self._player_id_trace = nil
   end
end

function TitlesComponent:_create_trait_listeners()
   self._delay_listener_timer = nil
   -- it's checking the traits in _update_traits already, no need to check a second time to see if they should be checked; just call it directly
   self._trait_added_listener = radiant.events.listen(self._entity, 'stonehearth_ace:trait_added', self, self._update_traits)
   self._trait_removed_listener = radiant.events.listen(self._entity, 'stonehearth_ace:trait_removed', self, self._update_traits)

   self:_update_traits()
end

function TitlesComponent:get_titles()
   return self._sv.titles
end

function TitlesComponent:get_latest_title()
   return self._sv.latest_title
end

function TitlesComponent:get_renown()
   return self._sv.renown
end

-- used by reembarking
function TitlesComponent:set_titles(titles)
   self._sv.titles = titles or {}
   self:_recalculate_renown()
end

function TitlesComponent:_recalculate_renown()
   local renown = 0
   if self._sv.titles then
      for title, rank in pairs(self._sv.titles) do
         renown = renown + (self:_get_title_renown(title, rank) or 0)
      end
   end

   self._sv.renown = renown
   self.__saved_variables:mark_changed()
   self:_update_component_info()
end

function TitlesComponent:has_title(title, rank)
   local title_rank = self._sv.titles[title]
   return title_rank and (not rank or title_rank >= rank)
end

function TitlesComponent:get_highest_rank(title)
   return title and self._sv.titles[title]
end

-- once bestowed, a title is never removed; it can only be increased in rank
function TitlesComponent:add_title(title, rank)
   if not self:has_title(title, rank) then
      rank = rank or 1
      self._sv.titles[title] = rank
      self._sv.latest_title = title
      self._sv.renown = self._sv.renown + (self:_get_title_renown(title, rank) - (self:_get_title_renown(title, (rank - 1)) or 0))
      self.__saved_variables:mark_changed()

      -- even if we're not selecting a new title now, we need to ensure that the entity has a custom name
      local unit_info = self._entity:add_component('stonehearth:unit_info')
      unit_info:ensure_custom_name()

      -- update component info details
      self:_update_component_info()

      self:_select_new_title(nil, title)

      if stonehearth.client_state:get_client_gameplay_setting(self._entity:get_player_id(), 'stonehearth_ace', 'show_new_title_notification', true) then
         self:_show_bulletin(title, rank)
      end
   end
end

function TitlesComponent:_update_component_info()
   -- what's the best way to do this? probably offload the work (building table of all the ranks' i18n data) onto the client if possible
   self._entity:add_component('stonehearth_ace:component_info'):set_component_detail('stonehearth_ace:titles', 'titles', {
         type = 'title_list',
         titles = self._sv.titles,
         titles_json = self._sv.titles_json,
         header = 'stonehearth_ace:component_info.stonehearth_ace.titles.all_earned_titles'
      }, {
         renown = self._sv.renown
      })
end

-- either criteria_change is specified (and not title), when changing the criteria in gameplay settings,
-- or only title is specified (don't need to specify rank because a new title will always be the highest rank)
function TitlesComponent:_select_new_title(criteria_change, title)
   local unit_info = self._entity:add_component('stonehearth:unit_info')
   -- don't need to specify rank with unit_info:select_title because a new title will always be the highest rank

   if stonehearth.client_state:get_client_gameplay_setting(self._entity:get_player_id(), 'stonehearth_ace', 'auto_select_new_titles', true) then
      local criteria = criteria_change or
            stonehearth.client_state:get_client_gameplay_setting(self._entity:get_player_id(), 'stonehearth_ace', 'title_selection_criteria')

      if criteria == 'latest' then
         local latest_title = self._sv.latest_title
         if latest_title then
            unit_info:select_title(latest_title)
         end
      elseif criteria == 'highest_renown' then
         if criteria_change then
            local highest_title = self:_get_highest_renown_title()
            if highest_title then
               unit_info:select_title(highest_title)
            end
         elseif title then
            if self:_get_title_renown(title, self._sv.titles[title]) > self:_get_current_title_renown() then
               unit_info:select_title(title)
            end
         end
      elseif title then
         unit_info:select_title(title)
      end
   end
end

function TitlesComponent:_get_title_renown(title, rank)
   local population = stonehearth.population:get_population(self._entity:get_player_id())
   local renown = population:get_title_renown(self._entity, title, rank)

   if renown then
      if self._braggart then
         renown = math.floor((renown * 1.1) + 0.5)
      elseif self._modest then
         renown = math.floor((renown * 0.75) + 0.5)
      end
   end

   return renown
end

function TitlesComponent:_get_current_title_renown()
   local current_title = self._entity:add_component('stonehearth:unit_info'):get_current_title()
   return current_title and current_title.renown or 0
end

function TitlesComponent:_get_highest_renown_title()
   local highest_title, highest_renown
   for title, rank in pairs(self._sv.titles) do
      local renown = self:_get_title_renown(title, rank)
      if not highest_renown or renown > highest_renown then
         highest_title = title
      end
   end
   return highest_title
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

function TitlesComponent:update_titles_json(recalculate_renown)
   local pop = stonehearth.population:get_population(self._entity:get_player_id())
   local titles_json = pop and pop:get_titles_json_for_entity(self._entity)
   if titles_json ~= self._sv.titles_json then
      self._sv.titles_json = titles_json

      if recalculate_renown then
         self:_recalculate_renown()
      else
         self.__saved_variables:mark_changed()
      end
   end
end

function TitlesComponent:_update_traits()
   local traits_component = self._entity:get_component('stonehearth:traits')
   if traits_component then
      local had_braggart = self._braggart or false
      local had_modest = self._modest or false
      self._braggart = traits_component:has_trait('stonehearth_ace:traits:braggart')
      self._modest = traits_component:has_trait('stonehearth_ace:traits:modest')

      if had_braggart ~= self._braggart or had_modest ~= self._modest then
         self:_recalculate_renown()
      end
   end
end

function TitlesComponent:_show_bulletin(title, rank)
   -- alert the player that they gained a title
   local player_id = self._entity:get_player_id()
   local pop = stonehearth.population:get_population(player_id)
   local title_rank_data = pop and pop:get_title_rank_data(self._entity, title, rank) or {}
   title_rank_data.renown = title_rank_data.renown or 0
   local is_citizen = pop and pop:is_citizen(self._entity)
   local message = is_citizen and 'i18n(stonehearth_ace:ui.game.bulletin.achievement_acquired_bulletin.new_title.message)'
                     or 'i18n(stonehearth_ace:ui.game.bulletin.achievement_acquired_bulletin.new_title.item_message)'

   local bulletin = stonehearth.bulletin_board:post_bulletin(player_id)
      :set_ui_view('StonehearthAceAchievementAcquiredBulletinDialog')
      :set_callback_instance(self)
      :set_type('achievement')
      :set_data({
         title = 'i18n(stonehearth_ace:ui.game.bulletin.achievement_acquired_bulletin.new_title.title)',
         header = 'i18n(stonehearth_ace:ui.game.bulletin.achievement_acquired_bulletin.new_title.header)',
         message = message,
         zoom_to_entity = self._entity,
         has_character_sheet = is_citizen
      })
      :set_active_duration('1h')
      :add_i18n_data('entity', self._entity)
      --:add_i18n_data('old_name', old_name)
      :add_i18n_data('new_title', title_rank_data)

   return bulletin
end

return TitlesComponent
