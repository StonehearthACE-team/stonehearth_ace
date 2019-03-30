local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local Town = require 'stonehearth.services.server.town.town'
local AceTown = class()

AceTown._ace_old__pre_activate = Town._pre_activate
function AceTown:_pre_activate()
   self:_ace_old__pre_activate()

   if not self._sv._total_travelers_visited then
      self._sv._total_travelers_visited = self._sv._num_travelers
   end
end

AceTown._ace_old__requirements_met = Town._requirements_met
function AceTown:_requirements_met(person, job_uri)
   local job_component = person:get_component('stonehearth:job')
   local player_id = radiant.entities.get_player_id(person)
   local base_job = stonehearth.player:get_default_base_job(player_id)

   -- if person already has a controller for that job
   if job_component:get_controller(job_uri) or job_uri == base_job then
      return true
   end

   -- convert to appropriate kingdom
   local player_id = radiant.entities.get_player_id(person)
   local job_index = stonehearth.player:get_jobs(player_id)
   local mod_job_uri = job_index[job_uri].description

   -- get desired job information
   local job_data = radiant.resources.load_json(mod_job_uri)

   -- if desired job's parent is worker
   if job_data.parent_job == base_job then
      return true
   end

   -- if there are multiple parents, check for each of them
   -- If we can't have the parent job, ignore that requirement.
   local parent_jobs = job_data.parent_jobs or {{job = job_data.parent_job, level_requirement = job_data.parent_level_requirement}}
   local allowable_jobs = job_component:get_allowed_jobs()
   if allowable_jobs then
      for id, parent_job in pairs(parent_jobs) do
         if not allowable_jobs[parent_job.job] then
            parent_jobs[parent_job.job] = nil
         end
      end
   end

   local one_of = nil
   for id, parent_job in pairs(parent_jobs) do
      local parent_controller = job_component:get_controller(parent_job.job)
      local required_level = parent_job.level_requirement or 0

      if parent_job.one_of then
         if one_of == nil then
            one_of = false
         end
         if parent_controller and parent_controller:get_job_level() >= required_level then
            one_of = true
         end
      else
         if parent_controller then
            -- if the parent doesn't meet the level requirement, it fails
            if parent_controller:get_job_level() < required_level then
               return false
            end
         else
            -- if there is no controller for the parent, it fails
            return false
         end
      end
   end

   -- if there were no allowable parent job requirements, or they were all met, it succeeds
   return one_of ~= false
end

function AceTown:register_entity_type(type, entity)
   if not self._sv._registered_entity_types then
      self._sv._registered_entity_types = {}
   end
   if not self._sv._registered_entity_types[type] then
      self._sv._registered_entity_types[type] = {}
   end
   self._sv._registered_entity_types[type][entity:get_id()] = true
   self.__saved_variables:mark_changed()
end

function AceTown:unregister_entity_type(type, entity)
   if self._sv._registered_entity_types and self._sv._registered_entity_types[type] then
      self._sv._registered_entity_types[type][entity:get_id()] = nil
      self.__saved_variables:mark_changed()
   end
end

function AceTown:unregister_entity_types(entity)
   if self._sv._registered_entity_types then
      for _, type_tbl in pairs(self._sv._registered_entity_types) do
         type_tbl[entity:get_id()] = nil
      end
   end
   self.__saved_variables:mark_changed()
end

function AceTown:is_entity_type_registered(type)
   local registered = self._sv._registered_entity_types and self._sv._registered_entity_types[type]
   return registered and next(registered) ~= nil
end

function AceTown:register_pasture_item(item, type)
   -- check this item's bounds to see if they fall within the bounds of any pastures
   -- ignore items that don't fully fit within a pasture, in order to prevent issues with items overlapping multiple pastures
   local item_reg = csg_lib.get_region_footprint(item:add_component('region_collision_shape'):get_region():get())
   local item_loc = radiant.entities.get_world_grid_location(item)
   local item_rot = radiant.entities.get_facing(item)

   if item_loc then
      item_reg = item_reg:rotated(item_rot):translated(item_loc)
      for _, pasture in pairs(self._animal_pastures) do
         local pasture_reg = csg_lib.get_region_footprint(pasture:add_component('region_collision_shape'):get_region():get())
         local pasture_loc = radiant.entities.get_world_grid_location(pasture)
         pasture_reg = pasture_reg:translated(pasture_loc)
         if csg_lib.are_equivalent_regions(item_reg, pasture_reg:intersect_region(item_reg)) then
            local pasture_comp = pasture:get_component('stonehearth:shepherd_pasture')
            pasture_comp:register_item(item, type)
            break
         end
      end
   end
end

function AceTown:unregister_pasture_item(item)
   -- just tell every pasture that this trough is gone
   for _, pasture in pairs(self._animal_pastures) do
      local pasture_comp = pasture:get_component('stonehearth:shepherd_pasture')
      pasture_comp:unregister_item(item:get_id())
   end
end

AceTown._ace_old_unregister_pasture = Town.unregister_pasture
function AceTown:unregister_pasture(pasture)
   self:_ace_old_unregister_pasture(pasture)
   
   if pasture then
      local pasture_reg = csg_lib.get_region_footprint(pasture:add_component('region_collision_shape'):get_region():get())
      local pasture_loc = radiant.entities.get_world_grid_location(pasture)
      pasture_reg = pasture_reg:translated(pasture_loc)

      -- make sure all troughs and beds are "popped" back into iconics
      -- also cancel placement of any ghost pasture_items
      local items = radiant.terrain.get_entities_in_region(pasture_reg)
      
      for id, item in pairs(items) do
         if item:get_component('stonehearth_ace:pasture_item') then
            self:remove_previous_task_on_item(item)
            self:pop_entity_into_iconic(item)
         else
            local ghost = item:get_component('stonehearth:ghost_form')
            if ghost and radiant.entities.get_component_data(ghost:get_root_entity_uri(), 'stonehearth_ace:pasture_item') then
               -- apparently ghosts just get killed to cancel placement
               radiant.entities.kill_entity(item)
            end
         end
      end
   end
end

function AceTown:pop_entity_into_iconic(entity)
   local root, iconic = entity_forms_lib.get_forms(entity)
   local location = radiant.entities.get_world_grid_location(root)
   if location then
      radiant.terrain.remove_entity(root)
      radiant.terrain.place_entity_at_exact_location(iconic, location)
   end
end

AceTown._ace_old_spawn_traveler = Town.spawn_traveler
function AceTown:spawn_traveler()
   self._sv._total_travelers_visited = self._sv._total_travelers_visited + 1

   return self:_ace_old_spawn_traveler()
end

function AceTown:get_persistence_data()
   local pop = stonehearth.population:get_population(self._sv.player_id)
   
   local data = {
      player_id = self._sv.player_id,
      town_name = self._sv.town_name,
      kingdom = pop:get_kingdom(),
      total_travelers_visited = self._sv._total_travelers_visited,
      shepherd_animals = self:_get_shepherd_animals_data(),
      farm_crops = self:_get_farm_crops_data(),
      scores = self:_get_scores_data(),
      jobs = self:_get_jobs_data(),
      elapsed_days = stonehearth.calendar:get_elapsed_days()
   }

   self:_add_citizen_persistence_data(data, pop)

   return data
end

function AceTown:_get_shepherd_animals_data()
   local animals = {}
   local all_animals = self:get_pasture_animals()
   for _, animal in pairs(all_animals) do
      local uri = animal:get_uri()
      animals[uri] = (animals[uri] or 0) + 1
   end
   return animals
end

function AceTown:_get_farm_crops_data()
   local crops = {}
   for _, farm in pairs(self._sv._farms) do
      local contents = farm:get_component('stonehearth:farmer_field'):get_contents()
      for x, col in pairs(contents) do
         for y, plot in pairs(col) do
            if plot.contents then
               local uri = plot.contents:get_uri()
               crops[uri] = (crops[uri] or 0) + 1
            end
         end
      end
   end
   return crops
end

function AceTown:_get_scores_data()
   local scores = {}
   local scores_data = stonehearth.score:get_scores_for_player(self._sv.player_id):get_score_data()
   
   scores.average_food = scores_data.average:contains('food') and scores_data.average:get('food') or nil
   scores.average_nutrition = scores_data.average:contains('nutrition') and scores_data.average:get('nutrition') or nil
   scores.average_safety = scores_data.average:contains('safety') and scores_data.average:get('safety') or nil
   scores.average_shelter = scores_data.average:contains('shelter') and scores_data.average:get('shelter') or nil

   scores.category_buildings = scores_data.category_scores:contains('buildings') and scores_data.category_scores:get('buildings') or nil

   scores.median_happiness = scores_data.median:contains('happiness') and scores_data.median:get('happiness') or nil

   scores.total_edibles = scores_data.total_scores:contains('edibles') and scores_data.total_scores:get('edibles') or nil
   scores.total_military_strength = scores_data.total_scores:contains('military_strength') and scores_data.total_scores:get('military_strength') or nil
   scores.total_net_worth = scores_data.total_scores:contains('net_worth') and scores_data.total_scores:get('net_worth') or nil

   return scores
end

function AceTown:_get_jobs_data()
   local counts = {}
   local jobs_controller = stonehearth.job:get_jobs_controller(self._sv.player_id)
   local crafter_count, fighter_count, worker_count = jobs_controller:get_worker_crafter_fighter_counts()
   counts.num_workers = worker_count
   counts.num_crafters = crafter_count
   counts.num_fighters = fighter_count
   counts.job_member_counts = jobs_controller:get_job_member_counts()

   return counts
end

function AceTown:_add_citizen_persistence_data(data, pop)
   local crafters = {}
   local min_level = stonehearth.constants.persistence.crafters.MIN_LEVEL

   for id, citizen in pop:get_citizens():each() do
      local job = citizen:get_component('stonehearth:job')
      local job_uri = job:get_job_uri()
      local job_level = job:get_current_job_level()
      -- we only care about citizens that are level 6+ at their current jobs
      -- (these are the noteworthy citizens that might become known across the land)
      if job_level >= min_level then
         local crafter_comp = citizen:get_component('stonehearth:crafter')
         if crafter_comp then
            local crafter_type = crafters[job_uri]
            if not crafter_type then
               crafter_type = {}
               crafters[job_uri] = crafter_type
            end
            table.insert(crafter_type,
            {
               name = radiant.entities.get_custom_name(citizen),
               level = job_level,   -- in case we decide to relax the level 6+ constraint
               best_crafts = crafter_comp:get_best_crafts()
            })
         end
      end
   end

   data.crafters = crafters
end

return AceTown
