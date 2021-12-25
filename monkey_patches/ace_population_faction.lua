local PopulationFaction = require 'stonehearth.services.server.population.population_faction'
local AcePopulationFaction = class()

local rng = _radiant.math.get_default_rng()
local IntegerGaussianRandom = require 'stonehearth.lib.math.integer_gaussian_random'
local gaussian_rng = IntegerGaussianRandom(rng)

AcePopulationFaction._ace_old_activate = PopulationFaction.activate
function AcePopulationFaction:activate()
   self:_ace_old_activate()

   -- load up titles for this faction
   self:_load_titles()

   if not self._sv.unlocked_abilities then
      self._sv.unlocked_abilities = {}
      self.__saved_variables:mark_changed()
   end

   if not self._sv._updated_town_name then
      self._sv._updated_town_name = true
      self:update_town_name()
   end

   self:_load_unlocked_abilities()
end

function AcePopulationFaction:_load_unlocked_abilities()
   if self._data then
      -- if none specified by the kingdom, load some default unlocked abilities
      local abilities = self._data.unlocked_abilities or stonehearth.constants.population.default_unlocked_abilities or {field_type_farm = true}
      for ability, unlocked in pairs(abilities) do
         if unlocked then
            self._sv.unlocked_abilities[ability] = true
         end
      end
      self.__saved_variables:mark_changed()
   end
end

function AcePopulationFaction:has_unlocked_ability(ability)
   return self._sv.unlocked_abilities[ability]
end

function AcePopulationFaction:unlock_ability(ability)
   self._sv.unlocked_abilities[ability] = true
   self.__saved_variables:mark_changed()
end

AcePopulationFaction._ace_old_set_kingdom = PopulationFaction.set_kingdom
function AcePopulationFaction:set_kingdom(kingdom)
   local no_kingdom = not self._sv.kingdom
   self:_ace_old_set_kingdom(kingdom)

   if no_kingdom then
      self:_load_titles()
      self:_load_unlocked_abilities()
   end

   return no_kingdom
end

AcePopulationFaction._ace_old_set_game_options = PopulationFaction.set_game_options
function AcePopulationFaction:set_game_options(options)
	self:_ace_old_set_game_options(options)

   if not self._sv._game_options.starting_items_container then
      self._sv._game_options.starting_items_container = self._data.starting_items_container or 'stonehearth_ace:containers:embark_wagon'
		if self._sv._game_options.starting_items_container == 'none' or self._sv._game_options.starting_items_container == '' then
			self._sv._game_options.starting_items_container = nil
		end
   end
end

AcePopulationFaction._ace_old_create_new_citizen_from_role_data = PopulationFaction.create_new_citizen_from_role_data
function AcePopulationFaction:create_new_citizen_from_role_data(role, role_data, gender, options)
   local citizen = self:_ace_old_create_new_citizen_from_role_data(role, role_data, gender, options)

   if options and options.foreign_population_uri then
      citizen:add_component('stonehearth:job'):set_population_override(options.foreign_population_uri)
   end

   -- the citizen has now been added, so update their titles json if necessary
   local titles = citizen:get_component('stonehearth_ace:titles')
   if titles then
      titles:update_titles_json()
   end
   self:_update_citizen_town_name(citizen)

   return citizen
end

function AcePopulationFaction.generate_town_name_from_pieces(town_pieces)
   local composite_name = 'Defaultville'

   --If we do not yet have the town data, then return a default town name
   if town_pieces then
      local prefix_chance = (town_pieces.prefix_chance == nil) and 40 or town_pieces.prefix_chance
      local prefixes = town_pieces.optional_prefix
      local base_names = town_pieces.town_name
      local suffix_chance = (town_pieces.suffix_chance == nil) and 80 or town_pieces.suffix_chance
      local suffix = town_pieces.suffix

      --make a composite
      local target_prefix = prefixes[rng:get_int(1, #prefixes)]
      local target_base = base_names[rng:get_int(1, #base_names)]
      local target_suffix = suffix[rng:get_int(1, #suffix)]

      if target_base then
         composite_name = target_base
      end

      if target_prefix and rng:get_int(1, 100) <= prefix_chance then
         composite_name = target_prefix .. ' ' .. composite_name
      end

      if target_suffix and rng:get_int(1, 100) <= suffix_chance then
         composite_name = composite_name .. target_suffix
      end
   end

   return composite_name
end

function AcePopulationFaction:update_town_name()
   for _, citizen in self._sv.citizens:each() do
      self:_update_citizen_town_name(citizen)
   end
end

function AcePopulationFaction:_update_citizen_town_name(citizen)
   if not self:is_npc() then
      local town = stonehearth.town:get_town(self._sv.player_id)
      if town and town:get_town_name_set() then
         local stats = citizen:get_component('stonehearth_ace:statistics')
         if stats then
            stats:set_stat('towns_lived', town:get_town_serial_number(), town:get_town_name())
         end
      end
   end
end

function AcePopulationFaction:create_new_foreign_citizen(foreign_population_uri, role, gender, options)
   role = role or 'default'
   local foreign_pop_json = radiant.resources.load_json(foreign_population_uri)
   local role_data = foreign_pop_json.roles[role]
   if not role_data then
      error(string.format('unknown role %s in population %s', role, foreign_population_uri))
   end
   options = options or {}
   options.foreign_population_uri = foreign_population_uri
   
   return self:create_new_citizen_from_role_data(role, role_data, gender, options)
end

function AcePopulationFaction:generate_random_name(gender, role_data)
   if not role_data[gender] then
      gender = stonehearth.constants.population.DEFAULT_GENDER
   end

   if role_data[gender].given_names then
      local first_names = ""

      first_names = role_data[gender].given_names

      local name = first_names[rng:get_int(1, #first_names)]

      local surnames = role_data[gender].surnames or role_data.surnames
      if surnames then
         local surname = surnames[rng:get_int(1, #surnames)]
         name = name .. ' ' .. surname
      end
      return name
   else
      return nil
   end
end

--Will show a simple notification that zooms to a citizen when clicked.
--will expire if the citizen isn't around anymore
-- override to add custom_data for current title
function AcePopulationFaction:show_notification_for_citizen(citizen, title, options)
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

function AcePopulationFaction:are_traits_valid(traits, population_override_uri)
   local check_traits = self:_get_flat_traits(population_override_uri)
   
   for _, trait in ipairs(traits) do
      if not check_traits[trait] then
         return false
      end
   end

   return true
end

-- instead of just having our kingdom's traits stored, we need to have a table indexed by kindom uri
function AcePopulationFaction:_load_traits()
   if self._data.traits_index then
      self._traits = radiant.resources.load_json(self._data.traits_index)
   end

   if not self._traits then
      self._traits = radiant.resources.load_json('stonehearth:traits_index')
   end
   
   self._flat_trait_index = self:_load_flat_trait_index(self._traits)
end

-- index is either a uri, nil to indicate we should load the kingdom json and get the index there, or false to indicate skipping to default
function AcePopulationFaction:_load_kingdom_traits(kingdom_uri)
   if not kingdom_uri or kingdom_uri == self._sv.kingdom then
      return
   end

   if not self._foreign_traits then
      self._foreign_traits = {}
      self._flat_foreign_traits = {}
   end
   
   if not self._foreign_traits[kingdom_uri] then
      local traits
      local index = radiant.resources.load_json(kingdom_uri).traits_index
      if index then
         traits = radiant.resources.load_json(index)
      end
      if not traits then
         traits = radiant.resources.load_json('stonehearth:traits_index')
      end

      local flat_traits = self:_load_flat_trait_index(traits)

      self._foreign_traits[kingdom_uri] = traits
      self._flat_foreign_traits[kingdom_uri] = flat_traits
   end
end

function AcePopulationFaction:_load_flat_trait_index(traits)
   local flat_traits = {}
   for group_name, group in pairs(traits.groups) do
      flat_traits[group_name] = group
   end
   for trait_name, trait in pairs(traits.traits) do
      flat_traits[trait_name] = trait
   end

   return flat_traits
end

function AcePopulationFaction:_get_traits(kingdom_uri)
   self:_load_kingdom_traits(kingdom_uri)

   if not kingdom_uri or kingdom_uri == self._sv.kingdom then
      return self._traits
   else
      return self._foreign_traits[kingdom_uri]
   end
end

function AcePopulationFaction:_get_flat_traits(kingdom_uri)
   self:_load_kingdom_traits(kingdom_uri)

   if not kingdom_uri or kingdom_uri == self._sv.kingdom then
      return self._flat_trait_index
   else
      return self._flat_foreign_traits[kingdom_uri]
   end
end

-- ACE: have to override this to change the reference to self._traits
-- Picks a trait at (uniformly) random from the list of available traits; if the
-- picked trait is incompatible with the list of current traits, that trait is
-- removed from the supplied list of available traits.  Otherwise, the set of available
-- traits is not affected; it is up to the caller to remove the successfully-returned
-- trait.
function AcePopulationFaction:_pick_random_trait(citizen, current_traits, available_traits, options)
   local function valid_trait(trait_uri, trait)
      for current_trait_uri, current_trait in pairs(current_traits) do
         -- Check for excluded traits.
         if current_trait.excludes and current_trait.excludes[trait_uri] then
            return false
         end
         if trait.excludes and trait.excludes[current_trait_uri] then
            return false
         end
         -- TODO(?) check for excluded groups?  Tags?
      end

      if trait.immigration_only and options.embarking then
         return false
      end
      if trait.gender and trait.gender ~= self:get_gender(citizen) then
         return false
      end

      return true
   end

   local trait_groups = self:_get_traits(options.foreign_population_uri).groups
   local n = radiant.size(available_traits)
   while n > 0 do
      local trait_uri = radiant.get_random_map_key(available_traits, rng)
      local group_name = nil

      if trait_groups[trait_uri] then
         group_name = trait_uri

         local group = available_traits[group_name]

         trait_uri = radiant.get_random_map_key(group, rng)

         if valid_trait(trait_uri, group[trait_uri]) then
            return trait_uri, group_name
         end
      else
         if valid_trait(trait_uri, available_traits[trait_uri]) then
            return trait_uri, nil
         end
      end

      -- No dice--the trait is in conflict.
      local group = nil
      if group_name then
         group = available_traits[group_name]
         group[trait_uri] = nil

         -- We cleaned up the group; now, overwrite trait_uri to possibly
         -- clean up the group's entry.
         trait_uri = group_name
      end

      if not group_name or not next(group) then
         available_traits[trait_uri] = nil
         -- We removed a top-level entry from the list of available traits,
         -- so, decrement the total we can look through.
         n = n - 1
      end
   end

   return nil, nil
end

function AcePopulationFaction:_assign_citizen_traits(citizen, options)
   local tc = citizen:get_component('stonehearth:traits')
   if options.suppress_traits or not tc then
      return
   end

   local num_traits = gaussian_rng:get_int(1, 3, 0.6)
   self._log:info('assigning %d traits', num_traits)

   local all_traits = radiant.deep_copy(self:_get_flat_traits(options.foreign_population_uri))
   local traits = {}
   local start = 1

   -- When doing embarkation trait assignment, make sure every hearthling
   -- gets a 'prime' trait (i.e. ensure we use at least K traits from the
   -- complete list of traits for K hearthlings).
   if options.embarking then
      local available_prime_traits = radiant.deep_copy(all_traits)

      -- Remove all the previously-assigned prime traits from our copy.
      for trait_uri, group_name in pairs(self._prime_traits) do
         if group_name and available_prime_traits[group_name] then
            available_prime_traits[group_name][trait_uri] = nil
            if not next(available_prime_traits[group_name]) then
               available_prime_traits[group_name] = nil
            end
         elseif available_prime_traits[trait_uri] then
            available_prime_traits[trait_uri] = nil
         end
      end

      local trait_uri, group_name = self:_pick_random_trait(citizen, traits, available_prime_traits, options)
      if not trait_uri then
         self._log:info('ran out of prime traits!')
         self._prime_traits = {}
         trait_uri, group_name = self:_pick_random_trait(citizen, traits, all_traits, options)
         assert(trait_uri)
      end
      self:_add_trait(traits, trait_uri, group_name, all_traits, tc)
      self._prime_traits[trait_uri] = group_name or false

      self._log:info('  prime trait %s', trait_uri)
      start = 2
   end

   for i = start, num_traits do
      local trait_uri, group_name = self:_pick_random_trait(citizen, traits, all_traits, options)
      if not trait_uri then
         self._log:info('ran out of traits!')
         break
      end

      self._log:info('  picked %s', trait_uri)
      self:_add_trait(traits, trait_uri, group_name, all_traits, tc)
   end
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
                     -- if the required_value is a time duration, parse it
                     if type(rank_data.required_value) == 'string' then
                        rank_data.required_value = stonehearth.calendar:parse_duration(rank_data.required_value)
                     end
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

   local name_tbl = titles and titles[stat_changed_args.category] and titles[stat_changed_args.category][stat_changed_args.name]
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

function AcePopulationFaction:get_job_index(population)
   local job_index = 'stonehearth:jobs:index'
   if self:is_npc() then
      job_index = 'stonehearth:jobs:npc_job_index'
   end

   -- if a population is specified, try to use that population's job index
   -- if it doesn't have one, it's depending on the default job index, so we don't want this population's job index redirect
   if population then
      local pop_data = radiant.resources.load_json(population)
      if pop_data and pop_data.job_index then
         job_index = pop_data.job_index
      end
   elseif self._data and self._data.job_index then
      job_index = self._data.job_index
   end

   return job_index
end

function AcePopulationFaction:get_parties()
   return self._sv.parties
end

function AcePopulationFaction:reconsider_all_individual_party_commands()
   for _, party in pairs(self._sv.parties) do
      stonehearth.combat_server_commands:reconsider_all_individual_party_commands(party)
   end
end

-- ACE: if it's a pet (e.g., combat pet that can patrol), it won't be a citizen
-- the entry point in the ui when someone clicks a check box to opt into or out of a job
-- we need to update our work_order map and notify the town
function AcePopulationFaction:change_work_order_command(session, response, work_order, citizen_id, checked)
   local citizen
   if self._sv.citizens:contains(citizen_id) then
      citizen = self._sv.citizens:get(citizen_id)
   else
      citizen = radiant.entities.get_entity(citizen_id)
   end

   if citizen and citizen:is_valid() then
      if checked == true then
         citizen:add_component('stonehearth:work_order'):enable_work_order(work_order)
      elseif checked == false then
         citizen:add_component('stonehearth:work_order'):disable_work_order(work_order)
      end
   end

   return true
end

return AcePopulationFaction
