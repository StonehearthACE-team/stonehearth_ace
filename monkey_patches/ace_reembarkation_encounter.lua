--[[
   This encounter asks the player to select citizens and items to carry over into
   future embarkations and saves them as a re-embark file in saved_objects.
]]

local Entity = _radiant.om.Entity

local GOLD_URI = 'stonehearth:loot:gold'

local log = radiant.log.create_logger('reembarkation_encounter')

local ReembarkationEncounter = require 'stonehearth.services.server.game_master.controllers.encounters.reembarkation_encounter'
local AceReembarkationEncounter = class()

function AceReembarkationEncounter:start(ctx, info)
   self._sv.ctx = ctx
   self._sv._info = info

   local opt_view = 'StonehearthReembarkationBulletinDialog'
   self._sv.bulletin_data = {}
   self._sv.bulletin_data.title = 'i18n(stonehearth:ui.game.bulletin.reembarkation.title)'
   self._sv.bulletin_data.on_confirm = '_on_confirm'
   self._sv.bulletin_data.on_reject = '_on_reject'

   self._sv.bulletin = stonehearth.bulletin_board:post_bulletin(ctx.player_id)
                                    :set_callback_instance(self)
                                    :set_sticky(true)
                                    :set_close_on_handle(false)
                                    :set_type(info.bulletin_type or 'reembark')

   self._sv.bulletin:set_data(self._sv.bulletin_data)
                    :set_ui_view(opt_view)
   self.__saved_variables:mark_changed()
end

-- ACE override to add pets to departees and lock them to their owners
function AceReembarkationEncounter:_on_confirm(session, request, reembark_choices)
   if self._sv.is_celebrating then
      return  -- Already confirmed.
   end

   local reembark_record = self:_construct_reembark_record(reembark_choices)
   
   self._sv.is_celebrating = true
   self._sv.departees = self:_get_departees(reembark_choices.citizens)
   self._sv.items_to_take = reembark_choices.items
   self:_start_farewell_party()
   
   if self._sv.bulletin then
      stonehearth.bulletin_board:remove_bulletin(self._sv.bulletin)
      self._sv.bulletin = nil
      self.__saved_variables:mark_changed()
   end
   
   return { spec_id = _radiant.sim.generate_uuid(), spec_record = reembark_record }
end

AceReembarkationEncounter._ace_old__start_farewell_party = ReembarkationEncounter._start_farewell_party
function AceReembarkationEncounter:_start_farewell_party()
   radiant.events.trigger(radiant, 'stonehearth:request_music_track', { player_id = self._sv.ctx.player_id, track = 'reembarkation' })

   self:_ace_old__start_farewell_party()
end

AceReembarkationEncounter._ace_old__end_farewell_party = ReembarkationEncounter._end_farewell_party
function AceReembarkationEncounter:_end_farewell_party()
   radiant.events.trigger(radiant, 'stonehearth:request_music_track', { player_id = self._sv.ctx.player_id, track = nil })

   self:_ace_old__end_farewell_party()
end

function AceReembarkationEncounter:_get_departees(citizens)
   -- start with a copy of the citizens
   local departees = radiant.shallow_copy(citizens)

   -- then go through and get all the pets, locking them to their current owners
   for _, citizen in pairs(citizens) do
      local pets = self:_lock_pets_to_owner(citizen)
      if pets then
         radiant.util.merge_into_table(departees, pets)
      end
   end

   return departees
end

function AceReembarkationEncounter:_lock_pets_to_owner(citizen)
   local pet_owner_comp = citizen:get_component('stonehearth:pet_owner')
   if pet_owner_comp then
      local pets = pet_owner_comp:get_pets()
      for id, pet in pairs(pets) do
         pet:add_component('stonehearth:pet'):lock_to_owner()
      end
      if next(pets) then
         return pets
      end
   end
end

function AceReembarkationEncounter:_kick_out_departees()
   for _, citizen in pairs(self._sv.departees) do
      if radiant.entities.exists(citizen) then
         stonehearth.ai:inject_ai(citizen, { ai_packs = { 'stonehearth_ace:ai_pack:departing' } })
         citizen:get_component('stonehearth:ai')
                :get_task_group('stonehearth:task_groups:solo:unit_control')
                :create_task('stonehearth:depart_visible_area', { give_up_after = '3h' })
                :start()
      end
   end
   
   stonehearth.calendar:set_timer('continue after departees departed', '2h', function()
         self._sv.departees = nil
         self._sv.resolved_out_edge = self._sv.ctx.encounter:get_info().out_edge
         self._sv.ctx.arc:trigger_next_encounter(self._sv.ctx)
         self.__saved_variables:mark_changed()
      end)
end

function AceReembarkationEncounter:_construct_reembark_record(reembark_choices)
   radiant.validator.expect.table.only_fields({'citizens', 'items'}, reembark_choices)
   radiant.validator.expect.table.types({citizens = 'table', items = 'table'}, reembark_choices)
   log:debug('Reembark choices from reembarkation_dialog.js: %s', radiant.util.table_tostring(reembark_choices))
   
   local town = stonehearth.town:get_town(self._sv.ctx.player_id)
   local town_name = town:get_town_name()
   local arrival_year = stonehearth.calendar:get_date_data().year + 1 - stonehearth.calendar:get_start_year()

   local reembark_record = { citizens = {}, items = {}, recipes = {}, name = town_name, year = arrival_year }
   -- TODO: Maybe carry over quest flags.

   local town_bonuses = town:get_active_town_bonuses()
   local attribute_modifiers = {}
   for _, bonus in pairs(town_bonuses) do
      if bonus.get_citizen_attribute_bonuses then
         local bonuses = bonus:get_citizen_attribute_bonuses() or {}
         for attribute, amount in pairs(bonuses) do
            attribute_modifiers[attribute] = (attribute_modifiers[attribute] or 0) + amount
         end
      end
   end

   -- Citizens
   for _, citizen in pairs(reembark_choices.citizens) do
      radiant.validator.assert_type(citizen, 'Entity')
      local citizen_record = self:_get_citizen_record(citizen)
      for attribute, amount in pairs(attribute_modifiers) do
         citizen_record.attributes[attribute] = (citizen_record.attributes[attribute] or 0) + amount
      end

      table.insert(reembark_record.citizens, citizen_record)
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

function AceReembarkationEncounter:_remove_items()
   local inventory = stonehearth.inventory:get_inventory(self._sv.ctx.player_id)
   for _, item in pairs(self._sv.items_to_take) do
      if item.uri == GOLD_URI then
         inventory:subtract_gold(stonehearth.constants.reembarkation.gold_per_bag * item.count)
      elseif item.remove then
         local success = inventory:try_remove_items(item.remove_uri or item.uri, item.count, nil, item.item_quality)
         if not success then
            inventory:try_remove_items(item.remove_uri or item.uri, item.count, 'stonehearth:basic_inventory_tracker', item.item_quality)
         end
      end
   end
end

function AceReembarkationEncounter:_get_citizen_record(citizen)
   -- leave job_levels separate from jobs data for backwards compatibility
   local job_levels = {}
   local jobs = {}
   for uri, job_controller in pairs(citizen:get_component('stonehearth:job'):get_all_controller()) do
      job_levels[uri] = job_controller:get_job_level()
      jobs[uri] = {
         category_profiencies = job_controller:get_category_proficiencies()
      }
   end

   local attributes_component = citizen:get_component('stonehearth:attributes')
   local attributes = {
      mind = attributes_component:get_unmodified_attribute('mind'),
      body = attributes_component:get_unmodified_attribute('body'),
      spirit = attributes_component:get_unmodified_attribute('spirit'),
   }

   local traits = {}
   for uri, trait in pairs(citizen:get_component('stonehearth:traits'):get_traits()) do
      traits[uri] = trait:get_reembark_args()
   end

   local customization_styles = {}
   for _, style in pairs(citizen:get_component('stonehearth:customization'):get_added_styles()) do
      customization_styles[style.subcategory] = style.style
   end

   local equipment = {}
   for _, obj in pairs(citizen:get('stonehearth:equipment'):get_all_dropable_items()) do
      local item_data = self:_get_customizable_entity_data(obj)
      local item_quality = obj:get_component('stonehearth:item_quality')
      item_data.item_quality = item_quality and item_quality:get_quality() or 1
      item_data.author = item_quality and item_quality:get_author_name()
      item_data.author_type = item_quality and item_quality:get_author_type()

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
      title_locked = data.title_locked,
      uri = data.uri,
      statistics = data.statistics,
      titles = data.titles,
		buffs = data.buffs,
      model_variant = data.model_variant or stonehearth.constants.population.DEFAULT_GENDER,
      customization = customization_styles,
      job_levels = job_levels,
      jobs = jobs,
      current_job = citizen:get_component('stonehearth:job'):get_job_uri(),
      allowed_jobs = citizen:get_component('stonehearth:job'):get_allowed_jobs(),
      population_override = population_override,
      attributes = attributes,
      traits = traits,
      item_preferences = citizen:get_component('stonehearth:appeal'):get_item_preferences(),
      item_preference_discovered_flags = citizen:get_component('stonehearth:appeal'):get_item_preference_discovered_flags(),
      equipment = equipment,
      pets = self:_get_pet_data(citizen),
   }
end

function AceReembarkationEncounter:_get_customizable_entity_data(entity)
   local unit_info_comp = entity:get_component('stonehearth:unit_info')

   local statistics
   local statistics_comp = entity:get_component('stonehearth_ace:statistics')
   if statistics_comp then
      statistics_comp:increment_stat('totals', 'reembarks', nil, nil, true)
      statistics = statistics_comp:get_statistics()
   end

   local titles_comp = entity:get_component('stonehearth_ace:titles')
   local titles = titles_comp and titles_comp:get_titles()
	
	local buffs_comp = entity:get_component('stonehearth:buffs')
	local buffs = buffs_comp and buffs_comp:get_reembarkable_buffs()
   
   return {
      uri = entity:get_uri(),
      model_variant = radiant.entities.get_model_variant(entity),
      name = unit_info_comp and unit_info_comp:get_custom_name(),
      custom_data = unit_info_comp and unit_info_comp:get_custom_data(),
      title_locked = unit_info_comp and unit_info_comp:get_title_locked(),
      statistics = statistics,
      titles = titles,
      buffs = buffs,
   }
end

function AceReembarkationEncounter:_get_pet_data(entity)
   local pet_owner_comp = entity:get_component('stonehearth:pet_owner')
   if pet_owner_comp then
      local pets = {}

      for id, pet in pairs(pet_owner_comp:get_pets()) do
         local pet_data = self:_get_customizable_entity_data(pet)
         -- record the id in case it needs to be referenced by something else, e.g., animal companion trait
         pet_data.entity_id = id
         table.insert(pets, pet_data)
      end

      if #pets > 0 then
         return pets
      end
   end
end

return AceReembarkationEncounter
