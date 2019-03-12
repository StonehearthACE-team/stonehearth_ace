local PopulationFaction = require 'stonehearth.services.server.population.population_faction'
local AcePopulationFaction = class()

AcePopulationFaction._ace_old_activate = PopulationFaction.activate
function AcePopulationFaction:activate()
   self:_ace_old_activate()

   -- load up titles for this faction
   self:_load_titles()
end

AcePopulationFaction._ace_old_set_kingdom = PopulationFaction.set_kingdom
function AcePopulationFaction:set_kingdom(kingdom)
   local no_kingdom = not self._sv.kingdom
   self:_ace_old_set_kingdom(kingdom)

   if no_kingdom then
      self:_load_titles()
   end
   return no_kingdom
end

AcePopulationFaction._ace_old_create_new_citizen_from_role_data = PopulationFaction.create_new_citizen_from_role_data
function AcePopulationFaction:create_new_citizen_from_role_data(role, role_data, gender, options)
   local citizen = self:_ace_old_create_new_citizen_from_role_data(role, role_data, gender, options)

   -- the citizen has now been added, so update their titles json if necessary
   local titles = citizen:get_component('stonehearth_ace:titles')
   if titles then
      titles:update_titles_json()
   end

   return citizen
end

--Will show a simple notification that zooms to a citizen when clicked.
--will expire if the citizen isn't around anymore
-- override to add custom_data for current title
function PopulationFaction:show_notification_for_citizen(citizen, title, options)
   local citizen_id = citizen:get_id()
   if not self._sv.bulletins[citizen_id] then
      self._sv.bulletins[citizen_id] = {}
   elseif self._sv.bulletins[citizen_id][title] then
      if options.ignore_on_repeat_add then
         return
      end
      --If a bulletin already exists for this citizen with this title, remove it to replace with the new one
      local bulletin_id = self._sv.bulletins[citizen_id][title]:get_id()
      stonehearth.bulletin_board:remove_bulletin(bulletin_id)
   end

   local town_name = stonehearth.town:get_town(self._sv.player_id):get_town_name()
   local notification_type = options and options.type or 'info'
   local message = options and options.message or ''

   self._sv.bulletins[citizen_id][title] = stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
            :set_callback_instance(self)
            :set_type(notification_type)
            :set_data({
               title = title,
               message = message,
               zoom_to_entity = citizen,
            })
            :add_i18n_data('citizen_custom_name', radiant.entities.get_custom_name(citizen))
            :add_i18n_data('citizen_display_name', radiant.entities.get_display_name(citizen))
            :add_i18n_data('citizen_custom_data', radiant.entities.get_custom_data(citizen))
            :add_i18n_data('town_name', town_name)

   self.__saved_variables:mark_changed()
end

function AcePopulationFaction:_load_titles()
   self._population_titles, self._statistics_population_titles = self:_load_titles_from_json(self._data.population_titles)
   self._item_titles, self._statistics_item_titles = self:_load_titles_from_json(self._data.item_titles)
end

function AcePopulationFaction:_load_titles_from_json(json_ref)
   local titles = {}
   local stats_titles = {}
   
   local json = json_ref and radiant.resources.load_json(json_ref)
   if json then
      for title, data in pairs(json) do
         if data.ranks then
            titles[title] = {}
            for _, rank_data in ipairs(data.ranks) do
               titles[title][rank_data.rank] = rank_data
            end

            -- load stats requirements, if there are any
            if data.requirement and data.requirement.statistics then
               local category = data.requirement.statistics.category
               local name = data.requirement.statistics.name
               local category_tbl = stats_titles[category]
               if not category_tbl then
                  category_tbl = {}
                  stats_titles[category] = category_tbl
               end
               local name_tbl = category_tbl[name]
               if not name_tbl then
                  name_tbl = {}
                  category_tbl[name] = name_tbl
               end

               name_tbl[title] = {}
               for _, rank_data in ipairs(data.ranks) do
                  if rank_data.required_value then
                     table.insert(name_tbl[title], rank_data)
                  end
               end

               -- sort each grouping of ranks in descending order so it's easy to find only the highest rank to apply
               table.sort(name_tbl[title], function(a, b)
                  return (a.required_value or 0) > (b.required_value or 0)
               end)
            end
         end
      end
   end

   return titles, stats_titles
end

function AcePopulationFaction:get_titles_json_for_entity(entity)
   if self:is_citizen(entity) then
      return self._data.population_titles
   else
      return self._data.item_titles
   end
end

function AcePopulationFaction:_get_titles_for_entity_type(entity)
   -- check if the entity is one of our citizens; if so, use the population titles; otherwise, use the item titles
   if self:is_citizen(entity) then
      return self._population_titles
   else
      return self._item_titles
   end
end

function AcePopulationFaction:_get_stats_titles_for_entity_type(entity)
   -- check if the entity is one of our citizens; if so, use the population titles; otherwise, use the item titles
   if self:is_citizen(entity) then
      return self._statistics_population_titles
   else
      return self._statistics_item_titles
   end
end

function AcePopulationFaction:get_title_rank_data(entity, title, rank)
   local titles = self:_get_titles_for_entity_type(entity)
   
   return titles[title] and titles[title][rank]
end

function AcePopulationFaction:get_titles_for_statistic(entity, stat_changed_args)
   local titles = self:_get_stats_titles_for_entity_type(entity)

   local name_tbl = titles[stat_changed_args.category] and titles[stat_changed_args.category][stat_changed_args.name]
   if name_tbl then
      local is_numerical = type(stat_changed_args.value) == 'number'
      -- if the value is numerical, we want to get the highest required_value rank (higher ranks automatically grant all lower ranks in a group)
      -- otherwise, we want to look for that specific value only to grant that rank
      local title_ranks = {}
      for title, ranks in pairs(name_tbl) do
         for _, rank_data in ipairs(ranks) do
            if (is_numerical and stat_changed_args.value >= rank_data.required_value) or 
                  (not is_numerical and stat_changed_args.value == rank_data.required_value) then
               title_ranks[title] = rank_data.rank
               break
            end
         end
      end
      return title_ranks
   end
end

return AcePopulationFaction
