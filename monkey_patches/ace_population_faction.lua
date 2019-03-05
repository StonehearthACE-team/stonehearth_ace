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

function AcePopulationFaction:_load_titles()
   self._statistics_population_titles = self:_load_titles_from_json(self._data.population_titles)
   self._statistics_item_titles = self:_load_titles_from_json(self._data.item_titles)
end

function AcePopulationFaction:_load_titles_from_json(json_ref)
   local titles = {}
   
   local json = json_ref and radiant.resources.load_json(json_ref)
   if json then
      for title, data in pairs(json) do
         -- for now we only care about titles that have a statistics requirement
         -- because that's how we'll be organizing and accessing them
         if data.requirement and data.requirement.statistics then
            local category = data.requirement.statistics.category
            local name = data.requirement.statistics.name
            local category_tbl = titles[category]
            if not category_tbl then
               category_tbl = {}
               titles[category] = category_tbl
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

   return titles
end

function AcePopulationFaction:get_titles_for_statistic(entity, stat_changed_args)
   -- check if the entity is one of our citizens; if so, use the population titles; otherwise, use the item titles
   local titles
   if self._sv.citizens:contains(entity:get_id()) then
      titles = self._statistics_population_titles
   else
      titles = self._statistics_item_titles
   end

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
