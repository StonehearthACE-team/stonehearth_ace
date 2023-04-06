local Entity = _radiant.om.Entity
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'
local healing_lib = require 'stonehearth_ace.ai.lib.healing_lib'
local build_util = require 'stonehearth.lib.build_util'
local rng = _radiant.math.get_default_rng()

local Town = require 'stonehearth.services.server.town.town'
local AceTown = class()

local SUSPENDED_BUFF = 'stonehearth:buffs:hidden:suspended'

AceTown._ace_old__pre_activate = Town._pre_activate
function AceTown:_pre_activate()
   -- this function is in a race condition with the suspendable component registering with the town
   -- so let the _suspendable_entities table get created when necessary and not potentially overridden here
   self._suspendable_entities = self._suspendable_entities or {}
   self._periodic_interaction_entities = {}
   self._building_material_collection_tasks = {}
   self._default_storage_listener = {}
   self._quest_storage_zones = {}

   self:_ace_old__pre_activate()

   if not self._sv._total_travelers_visited then
      self._sv._total_travelers_visited = self._sv._num_travelers
   end
end

AceTown._ace_old_activate = Town.activate
function AceTown:activate(loading)
   -- instead of calling the old function, make sure we pass in to suspend_town that we're loading
   --self:_ace_old_activate(loading)
   if loading then
      local player_id = self._sv.player_id
      local pop = stonehearth.population:get_population(player_id)
      if not pop:is_npc() and player_id ~= _radiant.sim.get_host_player_id() and pop:is_camp_placed() then
         -- If we are loading, suspend this town's hearthlings since the player isn't connected
         self:suspend_town(true)
      end
   end

   self:_create_default_storage_listeners()
end

AceTown._ace_old_post_activate = Town.post_activate
function AceTown:post_activate()
   self:_ace_old_post_activate()
   self._post_activated = true
end

AceTown._ace_old_destroy = Town.__user_destroy
function AceTown:destroy()
   self:_destroy_default_storage_listeners()
   self:_destroy_all_building_material_collection_tasks()
   self:_ace_old_destroy()
end

function AceTown:_destroy_default_storage_listeners()
   if self._default_storage_listener then
      for _, listener in pairs(self._default_storage_listener) do
         listener:destroy()
      end
   end
   self._default_storage_listener = {}
end

function AceTown:_destroy_all_building_material_collection_tasks()
   for _, tasks in pairs(self._building_material_collection_tasks) do
      for _, task in ipairs(tasks) do
         task:destroy()
      end
   end
   self._building_material_collection_tasks = {}
end

function AceTown:_destroy_default_storage_listener(storage_id)
   if self._default_storage_listener and self._default_storage_listener[storage_id] then
      self._default_storage_listener[storage_id]:destroy()
      self._default_storage_listener[storage_id] = nil
   end
end

function AceTown:_create_default_storage_listeners()
   if not self._sv.default_storage then
      self._sv.default_storage = {}
      self.__saved_variables:mark_changed()
   end

   for _, storage in pairs(self._sv.default_storage) do
      self:_create_default_storage_listener(storage)
   end
end

function AceTown:_create_default_storage_listener(storage)
   local storage_id = storage:get_id()
   self:_destroy_default_storage_listener(storage_id)

   self._default_storage_listener[storage_id] = radiant.events.listen(storage, 'radiant:entity:pre_destroy', function()
         -- if it gets destroyed, make it no longer the default storage
         self:remove_default_storage(storage_id)
      end)
end

AceTown._ace_old_set_town_name = Town.set_town_name
function AceTown:set_town_name(town_name, set_by_player)
   self:_ace_old_set_town_name(town_name, set_by_player)

   if set_by_player then
      local population = stonehearth.population:get_population(self._sv.player_id)
      population:update_town_name()
   end
end

AceTown._ace_old__requirements_met = Town._requirements_met
function AceTown:_requirements_met(person, job_uri)
   local job_component = person:get_component('stonehearth:job')
   local player_id = radiant.entities.get_player_id(person)
   local population_override = job_component:get_population_override()
   local base_job = stonehearth.player:get_default_base_job(player_id, population_override)

   -- if person already has a controller for that job
   if job_component:get_controller(job_uri) or job_uri == base_job then
      return true
   end

   -- convert to appropriate kingdom
   local job_index = stonehearth.player:get_jobs(player_id, population_override)
   local mod_job_uri = job_index[job_uri].description

   -- get desired job information
   local job_data = radiant.resources.load_json(mod_job_uri)

   -- if desired job's parent is worker
   if job_data.parent_job == base_job then
      return true
   end

   -- if there are multiple parents, check for each of them
   local parent_jobs = job_data.parent_jobs
   if parent_jobs then
      -- copy the table so we aren't overriding a cached resource
      parent_jobs = radiant.shallow_copy(parent_jobs)
   else
      parent_jobs = {{job = job_data.parent_job, level_requirement = job_data.parent_level_requirement}}
   end

   -- If we can't have the parent job, ignore that requirement.
   local allowable_jobs = job_component:get_allowed_jobs()
   if allowable_jobs then
      for id, parent_job in pairs(parent_jobs) do
         if not allowable_jobs[parent_job.job] then
            parent_jobs[id] = nil
         end
      end
   end

   local one_of = nil
   for id, parent_job in pairs(parent_jobs) do
      local parent_controller = job_component:get_controller(parent_job.job)
      local required_level = parent_job.level_requirement or 0

      if parent_job.enabled then
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
   end

   -- if there were no allowable parent job requirements, or they were all met, it succeeds
   return one_of ~= false
end

-- ACE: recalculate with the tags this entity was modifying
function AceTown:remove_placement_slot_entity(entity)
   local entry = self._placement_slot_entities[entity:get_id()]
   self._placement_slot_entities[entity:get_id()] = nil

   -- reset to zero for tags being passed in
   local placement_limitations = entry and entry.placement_limitations
   if placement_limitations then
      placement_limitations = radiant.shallow_copy(placement_limitations)
      for tag, max_placeable in pairs(placement_limitations) do
         placement_limitations[tag] = 0
      end
      self:_calculate_num_placement_slots(placement_limitations)
   end
end

-- ACE: removed unnecessary saved_variables mark_changed
function AceTown:register_limited_placement_item(entity, item_tag)
   local id = entity
   if type(entity) ~= 'number' then
      id = entity:get_id()
   end

   if not self._registered_limited_placement_items.ids[id] then
      local count = self._registered_limited_placement_items.item_tags[item_tag] or 0
      self._registered_limited_placement_items.item_tags[item_tag] = count + 1
      self._registered_limited_placement_items.ids[id] = {
         entity = entity,
         item_tag = item_tag
      }
      --self.__saved_variables:mark_changed()
      self:_calculate_num_placement_slots()
   end
end

function AceTown:unregister_limited_placement_item(entity, item_tag)
   local id = entity
   if type(entity) ~= 'number' then
      id = entity:get_id()
   end
   if self._registered_limited_placement_items.ids[id] then
      local count = self._registered_limited_placement_items.item_tags[item_tag] or 0
      self._registered_limited_placement_items.item_tags[item_tag] = math.max(0, count - 1)
      self._registered_limited_placement_items.ids[id] = nil
      --self.__saved_variables:mark_changed()
      self:_calculate_num_placement_slots()
   end
end

-- ACE: if a placement slot entity is removed,
-- pass in its placement limitations table with 0s for amounts
-- so that those tags will get updated even if no other placement slot entities modify them
function AceTown:_calculate_num_placement_slots(placement_slots)
   placement_slots = placement_slots and radiant.shallow_copy(placement_slots) or {}

   for id, data in pairs(self._placement_slot_entities) do
      if data and data.entity and data.entity:is_valid() then
         for tag, max_placeable in pairs(data.placement_limitations) do
            local count = placement_slots[tag]
            placement_slots[tag] = (placement_slots[tag] or 0) + max_placeable
         end
      else
         self._placement_slot_entities[id] = nil
      end
   end

   -- Recalculate which items have reached the item placement limit
   for tag, max_placeable in pairs(placement_slots) do
      self:_update_num_placed(tag, max_placeable)
   end
end

function AceTown:is_placeable(limit_data, id)
   -- if item we are trying to place is already placed in town,
   -- we must be trying to move the item, so allow that
   if self._registered_limited_placement_items.ids[id] then
     return true
  end
  -- if no placement slot entities available, make sure to still limit the number
  -- placeable items for this tag using default placement data
  if not next(self._placement_slot_entities) or not self._num_item_tags_placed[limit_data.tag] then
     self:_update_num_placed(limit_data.tag, limit_data.default or 0)
  end
  -- entry will be non-nil if we already hit the limit for this type of item
  local entry = self._num_item_tags_placed[limit_data.tag]
  return entry and entry.can_place,
         entry and entry.num_placed,
         entry and entry.max_placeable
end

function AceTown:register_entity_type(type_name, entity)
   if not self._sv._registered_entity_types then
      self._sv._registered_entity_types = {}
   end
   local type_tbl = self._sv._registered_entity_types[type_name]
   if not type_tbl then
      type_tbl = {}
      self._sv._registered_entity_types[type_name] = type_tbl
   end

   local id = entity:get_id()
   local is_first_registered = next(type_tbl) == nil
   type_tbl[id] = true
   
   radiant.events.trigger_async(self, 'stonehearth_ace:town:entity_type_registered', type_name)
   if is_first_registered then
      radiant.events.trigger_async(self, 'stonehearth_ace:town:entity_type_registered_first', type_name)
   end
end

function AceTown:unregister_entity_type(type_name, entity)
   if self._sv._registered_entity_types and self._sv._registered_entity_types[type_name] then
      local type_tbl = self._sv._registered_entity_types[type_name]
      local id = entity:get_id()
      if type_tbl[id] then
         type_tbl[id] = nil

         radiant.events.trigger_async(self, 'stonehearth_ace:town:entity_type_unregistered:' .. type_name)
         if not next(type_tbl) then
            radiant.events.trigger_async(self, 'stonehearth_ace:town:entity_type_unregistered_last:' .. type_name)
         end
      end
   end
end

function AceTown:unregister_entity_types(entity)
   if self._sv._registered_entity_types then
      for type_name, type_tbl in pairs(self._sv._registered_entity_types) do
         -- a little extra access overhead, but this will trigger the proper events
         self:unregister_entity_type(type_name, entity)
      end
   end
end

function AceTown:is_entity_type_registered(type_name)
   local registered = self._sv._registered_entity_types and self._sv._registered_entity_types[type_name]
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
            return pasture
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

-- don't actually pop out pasture items; instead, we'll deal with pasture items not being inside pastures
AceTown._ace_old_unregister_pasture = Town.unregister_pasture
function AceTown:unregister_pasture(pasture)
   self:_ace_old_unregister_pasture(pasture)
   
   if pasture then
      local pasture_comp = pasture:get_component('stonehearth:shepherd_pasture')
      for _, pasture_item in pairs(pasture_comp:get_pasture_items()) do
         pasture_item:add_component('stonehearth_ace:pasture_item'):unregister_with_town()
      end

      -- local pasture_reg = csg_lib.get_region_footprint(pasture:add_component('region_collision_shape'):get_region():get())
      -- local pasture_loc = radiant.entities.get_world_grid_location(pasture)
      -- pasture_reg = pasture_reg:translated(pasture_loc)

      -- -- make sure all troughs and beds are "popped" back into iconics
      -- -- also cancel placement of any ghost pasture_items
      -- local items = radiant.terrain.get_entities_in_region(pasture_reg)
      
      -- for id, item in pairs(items) do
      --    if item:get_component('stonehearth_ace:pasture_item') then
      --       self:remove_previous_task_on_item(item)
      --       self:pop_entity_into_iconic(item)
      --    else
      --       local ghost = item:get_component('stonehearth:ghost_form')
      --       if ghost and radiant.entities.get_component_data(ghost:get_root_entity_uri(), 'stonehearth_ace:pasture_item') then
      --          -- apparently ghosts just get killed to cancel placement
      --          radiant.entities.kill_entity(item)
      --       end
      --    end
      -- end
   end
end

function AceTown:pop_entity_into_iconic(entity)
   local root, iconic = entity_forms_lib.get_forms(entity)
   --local location = radiant.entities.get_world_grid_location(root)
   local local_location = radiant.entities.get_location_aligned(entity)
   if local_location then
      local parent = radiant.entities.get_parent(entity) or radiant.entities.get_root_entity()
      radiant.entities.remove_child(parent, entity)
      radiant.entities.move_to_grid_aligned(entity, Point3.zero)
      radiant.entities.add_child(parent, iconic, local_location)
   end
end

-- Returns true if the town has an available medic and we've successfully requested one
-- Returns false if no medics available
-- ACE: added rest_from_conditions parameter to verify that we have an applicable cure available before proceeding
function AceTown:try_request_medic(requester, rest_from_conditions)
   local requester_id = requester:get_id()
   if self._medic_requests[requester_id] then
      return true -- We've already requested a medic and gotten one. we're good
   end

   if self._medic_requests_count >= self._medic_slots_available then
      return false
   end

   --If the requester is a medic, they can heal themselves so they shouldn't try to request a medic
   if self._medics_available[requester_id] ~= nil then
      return false
   end

   -- check if there are conditions that need to be cured, and whether we have a cure available
   if rest_from_conditions then
      local conditions = healing_lib.get_conditions_needing_cure(requester)
      
      -- first check if there's a medic who can handle any of these conditions without an item
      if not self:can_any_medic_treat_any_conditions(conditions) and not self:is_any_healing_item_valid(requester, conditions) then
         return false
      end
   end

   self._log:detail('%s successfully requested a medic', requester)

   self._medic_requests[requester_id] = requester
   self._medic_requests_count = self._medic_requests_count + 1
   return true
end

function AceTown:can_any_medic_treat_any_conditions(conditions)
   for id, data in pairs(self._medics_available) do
      if data and data.entity and data.entity:is_valid() then
         if self:can_medic_treat_any_conditions(data.entity, conditions) then
            return true
         end
      end
   end

   return false
end

function AceTown:can_medic_treat_any_conditions(medic, conditions)
   if not medic or not medic:is_valid() then
      return false
   end

   local job = medic:get_component('stonehearth:job')
   local medic_capabilities = job and job:get_curr_job_controller():get_medic_capabilities()
   if not medic_capabilities or not medic_capabilities.cure_conditions then
      return false
   end

   -- go through conditions that need healing and check to see if the medic can cure any of them
   for _, condition in ipairs(conditions) do
      if medic_capabilities.cure_conditions[condition.condition] then
         return true
      end
   end

   return false
end

function AceTown:is_any_healing_item_valid(requester, conditions)
   local inventory = stonehearth.inventory:get_inventory(self._sv.player_id)
   if inventory then
      local guts, health = healing_lib.get_filter_guts_health_missing(requester)
      local tracker = inventory:add_item_tracker('stonehearth_ace:healing_item_tracker')
      for id, item in tracker:get_tracking_data():each() do
         if item and item:is_valid() then
            if self:is_healing_item_valid(item, requester, conditions, guts, health) then
               return true
            end
         end
      end
   end

   return false
end

function AceTown:is_healing_item_valid(item, requester, conditions, guts, health)
   if not conditions then
      conditions = healing_lib.get_conditions_needing_cure(requester)
   end
   if not guts or not health then
      guts, health = healing_lib.get_filter_guts_health_missing(requester)
   end

   return healing_lib.filter_healing_item(item, conditions, nil, guts, health) and stonehearth.ai:can_acquire_ai_lease(item, requester)
end

AceTown._ace_old_spawn_traveler = Town.spawn_traveler
function AceTown:spawn_traveler()
   self._sv._total_travelers_visited = self._sv._total_travelers_visited + 1

   return self:_ace_old_spawn_traveler()
end

function AceTown:_set_up_traveler(traveler)
   local equipment_clothes = radiant.entities.create_entity('stonehearth:outfits:trader_outfit')
	traveler:add_component('stonehearth:equipment'):equip_item(equipment_clothes)
	local hat = rng:get_int(1, 10)
	if hat > 5 then
		local equipment_hat = radiant.entities.create_entity('stonehearth_ace:outfits:trader_outfit:hat')  
		traveler:get_component('stonehearth:equipment'):equip_item(equipment_hat)	
	end
   traveler:add_component('stonehearth:traveler')
   traveler:add_component('stonehearth:appeal'):generate_item_preferences()
   traveler:add_component('stonehearth:object_owner'):add_ownership_type('bed')
end

function AceTown:get_pets()
   return self._town_pets
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
      unlocked_recipes = self:_get_unlocked_recipes_data(),
      elapsed_days = stonehearth.calendar:get_elapsed_days(),
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
            local uri
            if plot.contents then
               uri = plot.contents:get_uri()
            end
            if plot.post_harvest_contents then
               uri = plot.post_harvest_contents:get_uri()
            end
            if uri then
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

function AceTown:_get_unlocked_recipes_data()
   local recipes = {}

   local player_job_controller = stonehearth.job:get_player_job_controller(self._sv.player_id)
   for job_uri, job_info in pairs(player_job_controller:get_jobs()) do
      local unlocked_recipes = job_info:get_manually_unlocked()
      if unlocked_recipes then
         local recipe_keys = {}
         for recipe_id in pairs(unlocked_recipes) do
            table.insert(recipe_keys, recipe_id)
         end
         if next(recipe_keys) then
            recipes[job_uri] = recipe_keys
         end
      end
   end

   return recipes
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

-- this only handles actual instantiated actions! if the game is paused and you request a harvest task etc.,
-- this won't return true until the game is unpaused and the actual action is created, has been selected by the AI, and is running!
-- this won't happen unless someone is actually able to perform the task (e.g., pathing or other requirements are all met)
-- it might also be useful to patch TaskGroup:_create_task and :_on_task_destroyed to separately track whether tasks (not actions) exist
function AceTown:task_group_has_active_tasks(task_group)
   if type(task_group) == 'string' then
      task_group = self:get_task_group(task_group)
   end

   for task, _ in pairs(task_group._tasks) do
      if next(task._running_actions) then
         return true
      end
   end

   return false
end

function AceTown:is_player_town()
   local pop = stonehearth.population:get_population(self._sv.player_id)
   return pop and not pop:is_npc()
end

function AceTown:get_default_quest_storage_uri()
   -- if the kingdom has a default quest storage uri, return it
   local pop = stonehearth.population:get_population(self._sv.player_id)
   return pop and pop:get_default_quest_storage_uri()
end

function AceTown:get_default_storage()
   if self._post_activated then
      return self._sv.default_storage
   else
      return {}
   end
end

function AceTown:is_default_storage(storage)
   return self._sv.default_storage[storage:get_id()] ~= nil
end

function AceTown:add_default_storage(storage)
   if storage and storage:is_valid() and storage:get_component('stonehearth:storage') then
      self._sv.default_storage[storage:get_id()] = storage
      self.__saved_variables:mark_changed()
      storage:add_component('stonehearth_ace:input')
      self:_create_default_storage_listener(storage)
   else
      self._log:error('failed to add invalid storage entity %s to default storage')
   end
end

function AceTown:remove_default_storage(storage_id)
   self._sv.default_storage[storage_id] = nil
   self.__saved_variables:mark_changed()
   self:_destroy_default_storage_listener(storage_id)
end

function AceTown:register_quest_storage_zone(zone)
   if zone and zone:is_valid() then
      self._quest_storage_zones[zone:get_id()] = zone
   end
end

function AceTown:unregister_quest_storage_zone(zone_id)
   self._quest_storage_zones[zone_id] = nil
end

function AceTown:get_quest_storage_locations()
   local locations = {}
   for _, zone in pairs(self._quest_storage_zones) do
      local zone_component = zone:get_component('stonehearth_ace:quest_storage_zone')
      if zone_component then
         radiant.array_append(locations, zone_component:get_available_locations())
      end
   end
   return locations
end

function AceTown:get_periodic_interaction_entities()
   return self._periodic_interaction_entities
end

function AceTown:register_periodic_interaction_entity(entity)
   if entity and entity:is_valid() then
      self._periodic_interaction_entities[entity:get_id()] = entity
      radiant.events.trigger_async(self, 'stonehearth_ace:periodic_interaction:entity_added', entity)
   end
end

function AceTown:unregister_periodic_interaction_entity(entity)
   if entity then
      self._periodic_interaction_entities[entity:get_id()] = nil
   end
end

AceTown._ace_old_suspend_town = Town.suspend_town
function AceTown:suspend_town(loading)
   -- we're already suspended! don't double-suspend
   -- can happen if client fails to connect and then later succeeds
   --self._log:error('%s suspend_town(loading == %s)', self._sv.player_id, tostring(loading))
   if self._sv._is_suspended and not loading then
      return
   end

   --self._log:error('suspending suspendable entities for town %s...', self._sv.player_id)
   self:_suspend_suspendable_entities()

   --self._log:error('suspending town %s...', self._sv.player_id)
   self:_ace_old_suspend_town()
end

AceTown._ace_old_continue_town = Town.continue_town
function AceTown:continue_town()
   self:_ace_old_continue_town()
   
   self:_continue_suspendable_entities()
end

function AceTown:register_suspendable_entity(entity)
   if entity and entity:is_valid() then
      -- this fails on microworld because the town hasn't finished its loading yet
      if not self._suspendable_entities then
         self._suspendable_entities = {}
      end
      self._suspendable_entities[entity:get_id()] = entity

      -- if register is called after suspend applied on load
      if self._sv._is_suspended then
         local suspendable = entity:get_component('stonehearth_ace:suspendable')
         suspendable:town_suspended()
      end
   end
end

function AceTown:unregister_suspendable_entity(entity)
   if entity and self._suspendable_entities then
      self._suspendable_entities[entity:get_id()] = nil
   end
end

function AceTown:_suspend_suspendable_entities()
   for _, entity in pairs(self._suspendable_entities) do
      local suspendable = entity:get_component('stonehearth_ace:suspendable')
      suspendable:town_suspended()
   end
end

function AceTown:_continue_suspendable_entities()
   for _, entity in pairs(self._suspendable_entities) do
      local suspendable = entity:get_component('stonehearth_ace:suspendable')
      suspendable:town_continued()
   end
end

function AceTown:_suspend_animal(animal_id, animal)
   -- check if the animal has an ai component - if not, it's an egg (or something similar) that can't be sent away
   if animal:get_component('stonehearth:ai') then
      if radiant.entities.get_world_location(animal) then
         radiant.terrain.remove_entity(animal)
      end

      -- ACE: don't double-inject ai
      if not self._injected_ai[animal_id] then
         self._injected_ai[animal_id] = stonehearth.ai:inject_ai(animal, { actions = { 'stonehearth:actions:be_away_from_town' } })
      end

      local renewable_resource_component = animal:get_component('stonehearth:renewable_resource_node')
      if renewable_resource_component then
         renewable_resource_component:pause_resource_timer()
      end

      local pasture_tag = animal:get_component('stonehearth:equipment'):has_item_type('stonehearth:pasture_equipment:tag')
      if pasture_tag then
         local shepherded_component = pasture_tag:get_component('stonehearth:shepherded_animal')
         if shepherded_component:get_following() then
            local shepherd = shepherded_component:get_last_shepherd()
            local shepherd_class = shepherd:get_component('stonehearth:job'):get_curr_job_controller()
            shepherd_class:remove_trailing_animal(animal_id)

            shepherded_component:set_following(false)
         end
      end

      if not radiant.entities.has_buff(animal, SUSPENDED_BUFF) then
         radiant.entities.add_buff(animal, SUSPENDED_BUFF)
      end
   end
end

-- change placement to be within pasture area
function AceTown:_continue_animals(animals)
   for animal_id, animal in pairs(animals) do
      -- if it's an egg, it's already there, just resume its evolution
      if animal:get_component('stonehearth:ai') then
         local shepherded = stonehearth.shepherd:get_shepherded_animal_component(animal)
         local pasture = shepherded and shepherded:get_pasture()
         local pasture_component = pasture and pasture:get_component('stonehearth:shepherd_pasture')
         if pasture_component then
            local pasture_location = pasture_component:get_center_point()
            local pasture_size = pasture_component:get_size()
            local half_width = math.floor(pasture_size.x / 2)
            local half_length = math.floor(pasture_size.z / 2)
            local location = radiant.terrain.find_placement_point(pasture_location, 1, math.min(half_width, half_length))
            radiant.terrain.place_entity(animal, location)
         else
            self:_place_at_banner(animal)
         end

         local renewable_resource_component = animal:get_component('stonehearth:renewable_resource_node')
         if renewable_resource_component then
            renewable_resource_component:resume_resource_timer()
         end

         if self._injected_ai[animal_id] then
            self._injected_ai[animal_id]:destroy()
            self._injected_ai[animal_id] = nil
         end
      end

      radiant.entities.remove_buff(animal, SUSPENDED_BUFF)
   end
end

function AceTown:dispatch_citizen(citizen)
   local citizen_id = citizen:get_id()
   self:_prepare_citizen_for_dispatch(citizen_id, citizen)
   self:_suspend_citizen(citizen_id, citizen)
   self._dispatched_citizens[citizen_id] = true
end

function AceTown:_prepare_citizen_for_dispatch(citizen_id, citizen)
   local crafter_component = citizen:get_component('stonehearth:crafter')
   if crafter_component then
      crafter_component:clean_up_order()
   end
end

function AceTown:_should_auto_craft_items()
   return stonehearth.client_state:get_client_gameplay_setting(self._sv.player_id, 'stonehearth', 'building_auto_queue_crafters', true)
end

function AceTown:craft_and_place_item_type(entity_uri, placement_info)
   local ghost_entity = self:place_item_type(entity_uri, nil, placement_info)
   if ghost_entity and self:_should_auto_craft_items() then
      local player_jobs = stonehearth.job:get_jobs_controller(self._sv.player_id)
      local order = player_jobs:request_craft_product(entity_uri, 1)
      ghost_entity:add_component('stonehearth_ace:transform'):set_craft_order(order)
      return true
   end
end

function AceTown:craft_and_place_item_types(entity_uri, placement_infos)
   local ghosts = {}
   for _, placement_info in ipairs(placement_infos) do
      local ghost_entity = self:place_item_type(entity_uri, nil, placement_info)
      if ghost_entity then
         table.insert(ghosts, ghost_entity)
      end
   end

   if #ghosts > 0 and self:_should_auto_craft_items() then
      local player_jobs = stonehearth.job:get_jobs_controller(self._sv.player_id)
      local order = player_jobs:request_craft_product(entity_uri, #ghosts)
      for _, ghost in ipairs(ghosts) do
         ghost:add_component('stonehearth_ace:transform'):set_craft_order(order)
      end
      return true
   end
end

function AceTown:request_placement_task(iconic_uri, quality, require_exact)
   local quality_str = quality and tostring(quality) or 'any'
   local require_exact_str = require_exact and '_exact' or ''
   local key = iconic_uri .. stonehearth.constants.item_quality.KEY_SEPARATOR .. quality_str .. require_exact_str
   if not self._placement_tasks[key] then
      self._placement_tasks[key] = {
         count = 1,
         iconic_uri = iconic_uri, 
         quality = quality ~= nil and quality or -1,
         require_exact = require_exact,
      }
   else
      self._placement_tasks[key].count = self._placement_tasks[key].count + 1
   end

   radiant.events.trigger_async(self, 'stonehearth:town:place_item_types_changed')
end

function AceTown:unrequest_placement_task(iconic_uri, quality, require_exact)
   local quality_str = quality and tostring(quality) or 'any'
   local require_exact_str = require_exact and '_exact' or ''
   local key = iconic_uri .. stonehearth.constants.item_quality.KEY_SEPARATOR .. quality_str .. require_exact_str
   local task = self._placement_tasks[key]
   if not task then
      return
   end

   task.count = task.count - 1
   if task.count <= 0 then
      self._placement_tasks[key] = nil
   end
end

--Tell the harvesters to remove an item permanently from the world
--If there was already an outstanding task on the object, make sure to cancel it first.
-- ACE: only require a task if it's not an "item" (otherwise just destroy it)
function AceTown:clear_item(item)
   if not radiant.util.is_a(item, Entity) then
      return
   end

   -- Dont't clear items that aren't yours
   if radiant.entities.is_owned_by_another_player(item, self._sv.player_id) then
      return
   end

   self:remove_previous_task_on_item(item)

   if stonehearth.catalog:is_item(item:get_uri()) then
      radiant.entities.kill_entity(item, { source_id = self._sv.player_id })
      return
   end

   local clear_action = 'stonehearth:clear_item'
   local task_tracker_component = item:add_component('stonehearth:task_tracker')
   if task_tracker_component:is_activity_requested(clear_action) then
      return -- If someone has requested to clear this item already
   end

   task_tracker_component:cancel_current_task(false) -- false for don't trigger reconsider because we'll do so with the request task

   task_tracker_component:request_task(self._sv.player_id, nil, clear_action, "stonehearth:effects:clear_effect")
   task_tracker_component:cancel_task_if_entity_moves()
end

-- create a material collection task for each building/material
function AceTown:create_resource_collection_tasks(building_entity, resource_cost)
   local entity_id = building_entity:get_id()
   if entity_id and not self._building_material_collection_tasks[entity_id] then
      local tasks = {}
      for material, _ in pairs(resource_cost) do
         local task = self:create_task_for_group('stonehearth:task_groups:build',
                                                 'stonehearth_ace:collect_building_material',
                                                 { building = building_entity, material = material }):start()
         table.insert(tasks, task)
      end

      self._building_material_collection_tasks[entity_id] = tasks
   end
end

function AceTown:destroy_resource_collection_tasks(building_entity)
   local entity_id = building_entity:get_id()
   local tasks = self._building_material_collection_tasks[entity_id]
   if tasks then
      for _, task in ipairs(tasks) do
         task:destroy()
      end
      self._building_material_collection_tasks[entity_id] = {}
   end
end

return AceTown
