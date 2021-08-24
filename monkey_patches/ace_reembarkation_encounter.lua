--[[
   This encounter asks the player to select citizens and items to carry over into
   future embarkations and saves them as a re-embark file in saved_objects.
]]

local Entity = _radiant.om.Entity

local AceReembarkationEncounter = class()

function AceReembarkationEncounter:_construct_reembark_record(reembark_choices)
   radiant.validator.expect.table.only_fields({'citizens', 'items'}, reembark_choices)
   radiant.validator.expect.table.types({citizens = 'table', items = 'table'}, reembark_choices)
   
   local town_name = stonehearth.town:get_town(self._sv.ctx.player_id):get_town_name()

   local reembark_record = { citizens = {}, items = {}, recipes = {}, name = town_name }
   -- TODO: Maybe carry over quest flags.

   -- Citizens
   for _, citizen in pairs(reembark_choices.citizens) do
      radiant.validator.assert_type(citizen, 'Entity')
      table.insert(reembark_record.citizens, self:_get_citizen_record(citizen))
   end

   -- Items
   for _, item in pairs(reembark_choices.items) do
      radiant.validator.expect.table.types({uri = 'string', item_quality = 'number', count = 'number'}, item)
      -- TODO: Item author?
      table.insert(reembark_record.items, item)
   end

   -- Recipes/crops
   local player_job_controller = stonehearth.job:get_player_job_controller(self._sv.ctx.player_id)
   for job_uri, job_info in pairs(player_job_controller:get_jobs()) do
      local unlocked_recipes = job_info:get_manually_unlocked()
      if unlocked_recipes then
         local recipe_keys = {}
         for recipe_id in pairs(unlocked_recipes) do
            table.insert(recipe_keys, recipe_id)
         end
         if next(recipe_keys) then
            reembark_record.recipes[job_uri] = recipe_keys
         end
      end
   end

   return reembark_record
end

function AceReembarkationEncounter:_get_citizen_record(citizen)
   local job_levels = {}
   for uri, job_controller in pairs(citizen:get_component('stonehearth:job'):get_all_controller()) do
      job_levels[uri] = job_controller:get_job_level()
   end

   local attributes = {
      mind = citizen:get_component('stonehearth:attributes'):get_attribute('mind'),
      body = citizen:get_component('stonehearth:attributes'):get_attribute('body'),
      spirit = citizen:get_component('stonehearth:attributes'):get_attribute('spirit'),
   }

   local model_variant = citizen:get_component('render_info'):get_model_variant()  -- Gender
   if model_variant == '' then
      model_variant = stonehearth.constants.population.DEFAULT_GENDER
   end

   local customization_styles = {}
   for _, style in pairs(citizen:get_component('stonehearth:customization'):get_added_styles()) do
      customization_styles[style.subcategory] = style.style
   end

   local equipment = {}
   for _, obj in pairs(citizen:get('stonehearth:equipment'):get_all_dropable_items()) do
      local item_data = self:_get_customizable_entity_data(obj)
      item_data.item_quality = radiant.entities.get_item_quality(obj)

      table.insert(equipment, item_data)
   end

   -- if it doesn't have a population override, set it to this player's population
   -- that way, e.g., a goblin from a goblin player will be properly set as a goblin when reembarking as ascendancy
   local population_override = citizen:get_component('stonehearth:job'):get_population_override()
   if not population_override then
      population_override = stonehearth.population:get_population(self._sv.ctx.player_id):get_kingdom()
   end

   local data = self:_get_customizable_entity_data(citizen)

   return {
      name = data.name,
      custom_data = data.custom_data,
      uri = data.uri,
      statistics = data.statistics,
      titles = data.titles,
		buffs = data.buffs,
      model_variant = model_variant,
      customization = customization_styles,
      job_levels = job_levels,
      current_job = citizen:get_component('stonehearth:job'):get_job_uri(),
      allowed_jobs = citizen:get_component('stonehearth:job'):get_allowed_jobs(),
      population_override = population_override,
      attributes = attributes,
      traits = radiant.keys(citizen:get_component('stonehearth:traits'):get_traits()),
      item_preferences = citizen:get_component('stonehearth:appeal'):get_item_preferences(),
      item_preference_discovered_flags = citizen:get_component('stonehearth:appeal'):get_item_preference_discovered_flags(),
      equipment = equipment,
      -- TODO: Pets?
   }
end

function AceReembarkationEncounter:_get_customizable_entity_data(entity)
   local unit_info_comp = entity:get_component('stonehearth:unit_info')

   local statistics_comp = entity:get_component('stonehearth_ace:statistics')
   local statistics = statistics_comp and statistics_comp:get_statistics()

   local titles_comp = entity:get_component('stonehearth_ace:titles')
   local titles = titles_comp and titles_comp:get_titles()
	
	local buffs_comp = entity:get_component('stonehearth:buffs')
	local buffs = buffs_comp and buffs_comp:get_reembarkable_buffs()
   
   return {
      uri = entity:get_uri(),
      name = unit_info_comp and unit_info_comp:get_custom_name(),
      custom_data = unit_info_comp and unit_info_comp:get_custom_data(),
      statistics = statistics,
      titles = titles,
      buffs = buffs,
   }
end

return AceReembarkationEncounter
