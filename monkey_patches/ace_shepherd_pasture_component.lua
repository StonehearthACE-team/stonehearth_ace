local ShepherdPastureComponent = require 'stonehearth.components.shepherd_pasture.shepherd_pasture_component'
local AceShepherdPastureComponent = class()
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('shepherd_pasture')
local WEATHER_CHECK_TIME = '05:30am+2h' -- one hour after weather service has changed the weather
local DEFAULT_GRASS_SPAWN_RATE = '11h+2h'
local GRASS_HARVEST_TIME = '2h'

AceShepherdPastureComponent._ace_old_activate = ShepherdPastureComponent.activate
function AceShepherdPastureComponent:activate()
   self:_ace_old_activate()
   
   if not self._sv._queued_slaughters then
      self._sv.harvest_animals_renewable = true
      self._sv.harvest_grass = false
      self._sv.maintain_animals = self:get_max_animals()
      self._sv._queued_slaughters = {}
      self:_set_has_renewable()
      self.__saved_variables:mark_changed()
   end

   self._pasture_items = {}
   self._empty_troughs = {}
   self._fed_troughs = {}
   self._trough_listeners = {}
   
   self._weather_check_alarm = stonehearth.calendar:set_alarm(WEATHER_CHECK_TIME, function()
      self:_recalculate_duration()
   end)

   self._animal_sleep_alarm = stonehearth.calendar:set_alarm(stonehearth.constants.sleep.BEDTIME_START_HOUR, function()
      self:_make_animals_sleepy()
   end)
   
   self._grass_harvest_timer = stonehearth.calendar:set_interval('pasture grass harvest', GRASS_HARVEST_TIME, function()
      if self._sv.harvest_grass then
         self:_try_harvesting_grass()
      end
   end)

   if self._sv.harvest_grass then
      self:_try_harvesting_grass()
   end

   self:_start_grass_spawn()

   if self._sv.pasture_type then
      self:_register_with_town()
   end
end

-- overriding to get rid of registering with the town; we need to do that in :activate()
function AceShepherdPastureComponent:post_activate()
   if self._sv.pasture_type then
      self:set_feed(self._sv._current_feed)
      self:_create_pasture_tasks()

      for id, animal_data in pairs(self._sv.tracked_critters) do
         local animal = animal_data.entity
         self:_create_harvest_task(animal)
      end
      --self:_register_with_town()
   end
end

-- for some reason, overriding the destroy function doesn't work, so we have to override this one that only gets called during destroy
AceShepherdPastureComponent._ace_old__unregister_with_town = ShepherdPastureComponent._unregister_with_town
function AceShepherdPastureComponent:_unregister_with_town()
	self:_ace_old__unregister_with_town()

	-- destroy the add_grass timer
	self:_destroy_grass_spawn_timer()

	if self._weather_check_alarm then
		self._weather_check_alarm:destroy()
		self._weather_check_alarm = nil
   end

   if self._animal_sleep_alarm then
		self._animal_sleep_alarm:destroy()
		self._animal_sleep_alarm = nil
   end

   if self._grass_harvest_timer then
      self._grass_harvest_timer:destroy()
      self._grass_harvest_timer = nil
   end

   -- destroy trough listeners
   for id, _ in pairs(self._trough_listeners) do
      self:_destroy_trough_listener(id)
   end
end

function AceShepherdPastureComponent:_find_all_grass()
   -- this is a pretty hacky way of doing this, but I don't want to track all the different stages
   local grass_uri = self:_get_grass_uri()
	local filter_fn = function(entity)
		return string.sub(entity:get_uri(), 1, string.len(grass_uri)) == grass_uri
	end

	local size = self:get_size()
	local world_loc = radiant.entities.get_world_grid_location(self._entity)
	local cube = Cube3(world_loc, world_loc + Point3(size.x, 1, size.z))
	local region = Region3(cube)
	return radiant.terrain.get_entities_in_region(region, filter_fn)
end

-- called by the shepherd service once the field is created
function AceShepherdPastureComponent:post_creation_setup()
   -- NO, DON'T spawn grass when it's created
   -- spawn a few grass if possible
	-- determine the amount of grass in the pasture and use that instead of the total area
	--local grass = self:_find_grass_spawn_points()
	--local num_to_spawn = #grass / 200
   --self:_spawn_grass(num_to_spawn, grass)
   
   self._sv.harvest_animals_renewable = true
   self._sv.harvest_grass = false
   self._sv.maintain_animals = self:get_max_animals()
   self._sv._queued_slaughters = {}
   self.__saved_variables:mark_changed()
end

AceShepherdPastureComponent._ace_old_set_pasture_type_command = ShepherdPastureComponent.set_pasture_type_command
function AceShepherdPastureComponent:set_pasture_type_command(session, response, new_animal_type)
   local result = self:_ace_old_set_pasture_type_command(session, response, new_animal_type)

   if result then
      self:_set_has_renewable()
      self._sv.maintain_animals = self:get_max_animals()
      self._sv._queued_slaughters = {}

      self:_claim_animals_in_pasture()
   end

   return result
end

function AceShepherdPastureComponent:_claim_animals_in_pasture()
   -- reclaim any animals matching the new animal type (and any of its younger stages)
   local uri = self._pasture_data[self._sv.pasture_type].reproduction_uri or self._sv.pasture_type
   local uris = {}
   uris[uri] = true
   uris[self._sv.pasture_type] = true

   -- go through evolve data and keep loading entity data until there is no more or we get one we already had (loop)
   local evolve_data = radiant.entities.get_entity_data(uri, 'stonehearth:evolve_data')
   while evolve_data do
      uri = evolve_data.next_stage
      evolve_data = uri and not uris[uri] and radiant.entities.get_entity_data(uri, 'stonehearth:evolve_data')
      if uri then
         uris[uri] = true
      end
   end

   local filter_fn = function(entity)
		return uris[entity:get_uri()]
	end

	local size = self:get_size()
	local world_loc = radiant.entities.get_world_grid_location(self._entity)
	local cube = Cube3(world_loc, world_loc + Point3(size.x, 1, size.z))
	local region = Region3(cube)
   local animals = radiant.terrain.get_entities_in_region(region, filter_fn)
   
   self:convert_and_add_animals(animals)
end

AceShepherdPastureComponent._ace_old_add_animal = ShepherdPastureComponent.add_animal
function AceShepherdPastureComponent:add_animal(animal)
   self:_ace_old_add_animal(animal)
   local rrn = animal:get_component('stonehearth:renewable_resource_node')
   if rrn then
      rrn:auto_request_harvest()
   end
   self:_consider_maintain_animals()
end

function AceShepherdPastureComponent:convert_and_add_animals(animals)
   for _, animal in pairs(animals) do
      local equipment_component = animal:add_component('stonehearth:equipment')
      local pasture_collar = radiant.entities.create_entity('stonehearth:pasture_equipment:tag')
      equipment_component:equip_item(pasture_collar)
      local shepherded_animal_component = pasture_collar:get_component('stonehearth:shepherded_animal')
      shepherded_animal_component:set_animal(animal)
      shepherded_animal_component:set_pasture(self._entity)

      self._sv.tracked_critters[animal:get_id()] = {entity = animal}
      radiant.entities.set_player_id(animal, self._entity)
      self._sv.num_critters = self._sv.num_critters + 1
      self:_listen_for_renewables(animal)
      self:_listen_for_hungry_critter(animal)
      --self:_create_harvest_task(animal)
   end

   self:_calculate_reproduction_timer()
   self:_consider_maintain_animals()
   self:_update_score()

   self.__saved_variables:mark_changed()
   radiant.events.trigger(self._entity, 'stonehearth:on_pasture_animals_changed', {})
   stonehearth.ai:reconsider_entity(self._entity, 'pasture animal count changed')
end

AceShepherdPastureComponent._ace_old_remove_animal = ShepherdPastureComponent.remove_animal
function AceShepherdPastureComponent:remove_animal(animal_id)
   self:_ace_old_remove_animal(animal_id)

   self._sv._queued_slaughters[animal_id] = nil
   self.__saved_variables:mark_changed()
end

function AceShepherdPastureComponent:_set_has_renewable()
   if self._sv.pasture_type and radiant.entities.get_component_data(self._sv.pasture_type, 'stonehearth:renewable_resource_node') then
      self._sv.critter_type_has_renewable = true
   else
      self._sv.critter_type_has_renewable = false
   end
end

function AceShepherdPastureComponent:_get_adult_count()
   local count = 0
   for id, critter in pairs(self._sv.tracked_critters) do
      local animal = critter.entity
      local age = radiant.entities.get_entity_data(animal, 'stonehearth:evolve_data')
      local stage = (age and age.current_stage) or "adult"
      if stage == 'adult' then
         count = count + 1
      end
   end
   return count
end

function AceShepherdPastureComponent:_consider_maintain_animals()
   local num_queued = radiant.size(self._sv._queued_slaughters)
   local num_adults = self:_get_adult_count()
   local num_to_slaughter = num_adults - (self._sv.maintain_animals + num_queued)
   
   log:debug('_consider_maintain_animals: %s queued, %s to slaughter', num_queued, num_to_slaughter)
   if num_to_slaughter > 0 then
      -- just process through the animals with the normal iterator and try to harvest them
      -- first skip over named animals and renewably-harvestable animals
      num_to_slaughter = self:_try_slaughter(num_to_slaughter, true, true)
      num_to_slaughter = self:_try_slaughter(num_to_slaughter, true, false)
      num_to_slaughter = self:_try_slaughter(num_to_slaughter, false, true)
      num_to_slaughter = self:_try_slaughter(num_to_slaughter, false, false)
   elseif num_to_slaughter < 0 then
      -- we've queued up too many! probably user increased the maintain level after slaughter requests went out
      for id, _ in pairs(self._sv._queued_slaughters) do
         self._sv._queued_slaughters[id] = nil
         local critter = self._sv.tracked_critters[id]
         if critter and critter.entity and critter.entity:is_valid() then
            local resource_component = critter.entity:get_component('stonehearth:resource_node')
            if resource_component and resource_component:cancel_harvest_request() then
               num_to_slaughter = num_to_slaughter + 1
               if num_to_slaughter > -1 then
                  break
               end
            end
         end
      end
   else
      return
   end

   self.__saved_variables:mark_changed()
end

function AceShepherdPastureComponent:_try_slaughter(num_to_slaughter, not_if_named, not_if_renewably_harvestable)
   if num_to_slaughter > 0 then
      for id, critter in pairs(self._sv.tracked_critters) do
         if not self._sv._queued_slaughters[id] then
            if self:_request_slaughter_animal(critter.entity, not_if_named, not_if_renewably_harvestable) then
               num_to_slaughter = num_to_slaughter - 1
               if num_to_slaughter < 1 then
                  break
               end
            end
         end
      end
   end
   return num_to_slaughter
end

function AceShepherdPastureComponent:_request_slaughter_animal(animal, not_if_named, not_if_renewably_harvestable)
   if not animal:is_valid() then
      return false
   end
   
   if not_if_named then
      if radiant.entities.get_custom_name(animal) ~= '' then
         return false
      end
   end

   if not_if_renewably_harvestable then
      local renewable_resource_component = animal:get_component('stonehearth:renewable_resource_node')
      if renewable_resource_component and renewable_resource_component:is_harvestable() then
         return false
      end
   end
	
   local resource_component = animal:get_component('stonehearth:resource_node')
   if resource_component and resource_component:is_harvestable() then
      -- but don't request it on animals that are currently following a shepherd
      local pasture_tag = animal:get_component('stonehearth:equipment'):has_item_type('stonehearth:pasture_equipment:tag')
      local shepherded_component = pasture_tag and pasture_tag:get_component('stonehearth:shepherded_animal')
      if shepherded_component and shepherded_component:get_following() then
         return false
      end

      resource_component:request_harvest(self._entity:get_player_id())
      self._sv._queued_slaughters[animal:get_id()] = true
      return true
   end
end

AceShepherdPastureComponent._ace_old__create_harvest_task = ShepherdPastureComponent._create_harvest_task
function AceShepherdPastureComponent:_create_harvest_task(target)
   -- actually, just don't do this, ace_renewable_resource_node takes care of it (and has to for the spawn_immediately things anyway)
   --[[
   if self._sv.harvest_animals_renewable then
      log:debug('harvest_animals_renewable = true, harvesting %s', target)
      self:_ace_old__create_harvest_task(target)
   end
   ]]
end

function AceShepherdPastureComponent:_make_animals_sleepy()
   for id, critter in pairs(self._sv.tracked_critters) do
      local animal = critter.entity
      local resources = animal:is_valid() and animal:get_component('stonehearth:expendable_resources')
      if resources then
         local sleepiness = resources:get_value('sleepiness')
         if sleepiness and sleepiness < 25 then
            resources:set_value('sleepiness', sleepiness / 2 + 15)
         end
      end
   end
end

function AceShepherdPastureComponent:get_harvest_animals_renewable()
   return self._sv.harvest_animals_renewable
end

function AceShepherdPastureComponent:set_maintain_animals(value)
   if self._sv.maintain_animals ~= value then
      self._sv.maintain_animals = value
      self.__saved_variables:mark_changed()

      self:_consider_maintain_animals()
   end
end

function AceShepherdPastureComponent:set_harvest_animals_renewable(value)
   if self._sv.harvest_animals_renewable ~= value then
      self._sv.harvest_animals_renewable = value
      self.__saved_variables:mark_changed()

      for id, animal_data in pairs(self._sv.tracked_critters) do
         local animal = animal_data.entity
         if value then
            self:_ace_old__create_harvest_task(animal)
         else
            self:_cancel_harvest_task(animal)
         end
      end
   end
end

function AceShepherdPastureComponent:set_harvest_grass(value)
   if self._sv.harvest_grass ~= value then
      self._sv.harvest_grass = value
      self.__saved_variables:mark_changed()

      -- check immediately for any harvestable grass
      self:_try_harvesting_grass()
   end
end

function AceShepherdPastureComponent:_cancel_harvest_task(target)
   local renewable_resource_component = target:get_component('stonehearth:renewable_resource_node')
   if renewable_resource_component then
      renewable_resource_component:cancel_harvest_request()
   end
end

function AceShepherdPastureComponent:_try_harvesting_grass()
   local player_id = self._entity:get_player_id()
   local all_grass = self:_find_all_grass()
   local harvest = self._sv.harvest_grass

   for _, grass in pairs(all_grass) do
      local resource_component = grass:get_component('stonehearth:resource_node')
      if resource_component then
         if harvest then
            resource_component:request_harvest(player_id)
         else
            resource_component:cancel_harvest_request()
         end
      end
   end
end

function AceShepherdPastureComponent:_find_grass_spawn_points()
	local grass = {}
	local size = self:get_size()
	local world_loc = radiant.entities.get_world_grid_location(self._entity)
	for x = 1, size.x do
		for z = 1, size.z do
			local location = world_loc + Point3(x - 1, -1, z - 1)
			local kind = radiant.terrain.get_block_kind_at(location)
			if kind == 'grass' then
				table.insert(grass, location)
			end
		end
	end

	return grass
end

AceShepherdPastureComponent._ace_old__create_pasture_tasks = ShepherdPastureComponent._create_pasture_tasks
function AceShepherdPastureComponent:_create_pasture_tasks()
   self:_ace_old__create_pasture_tasks()
   
   local town = stonehearth.town:get_town(self._entity)

   local feed_trough_task = town:create_task_for_group(
      'stonehearth:task_groups:herding',
      'stonehearth_ace:feed_pasture_trough',
      {pasture = self._entity})
         :set_source(self._entity)
         :start()
   table.insert(self._added_pasture_tasks, feed_trough_task)
end

function AceShepherdPastureComponent:_start_grass_spawn()
   -- if the timer already existed, rebind it
   if self._sv._grass_spawn_timer and self._sv._grass_spawn_timer.bind then
      self._sv._grass_spawn_timer:bind(function()
            self:_spawn_grass()
         end)
   else
      self:_destroy_grass_spawn_timer()
		self:_setup_grass_spawn_timer()
	end
end

function AceShepherdPastureComponent:_setup_grass_spawn_timer()
	local spawn_period = self:_calculate_grass_spawn_period()
   self._sv._grass_spawn_timer = stonehearth.calendar:set_persistent_timer("pasture spawn grass", spawn_period, radiant.bind(self, '_spawn_grass'))
   self.__saved_variables:mark_changed()
end

function AceShepherdPastureComponent:_destroy_grass_spawn_timer()
	if self._sv._grass_spawn_timer then
		self._sv._grass_spawn_timer:destroy()
      self._sv._grass_spawn_timer = nil
      self.__saved_variables:mark_changed()
	end
end

function AceShepherdPastureComponent:_recalculate_duration()
	if self._sv._grass_spawn_timer then
		local old_duration = self._sv._grass_spawn_timer:get_duration()
		local old_expire_time = self._sv._grass_spawn_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration

		local spawn_period = self:_get_base_grass_spawn_period()
		local old_progress = self:_get_current_spawn_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv._grass_spawn_recalculate_progress = old_progress + new_progress
		local time_remaining = math.max(0, spawn_period * (1 - self._sv._grass_spawn_recalculate_progress))
		local scaled_time_remaining = self:_calculate_grass_spawn_period(time_remaining)
		self:_destroy_grass_spawn_timer()
      self._sv._grass_spawn_timer = stonehearth.calendar:set_persistent_timer("pasture spawn grass", scaled_time_remaining, radiant.bind(self, '_spawn_grass'))
      self.__saved_variables:mark_changed()
	end
end

function AceShepherdPastureComponent:_get_current_spawn_recalculate_progress()
	return self._sv._grass_spawn_recalculate_progress or 0
end

function AceShepherdPastureComponent:_calculate_grass_spawn_period(spawn_period)
	if not spawn_period then
		spawn_period = self:_get_base_grass_spawn_period()
	end
	-- This applies weather, biome, and town vitality multipliers
	spawn_period = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), spawn_period)
	return spawn_period
end

function AceShepherdPastureComponent:_apply_season_multiplier(spawn_period)
	return spawn_period
end

function AceShepherdPastureComponent:_get_base_grass_spawn_period()
	local spawn_period = radiant.entities.get_json(self).grass_spawn_period or DEFAULT_GRASS_SPAWN_RATE
	return stonehearth.calendar:parse_duration(spawn_period)
end

function AceShepherdPastureComponent:_spawn_grass(count, spawn_locations)
	if not count then
		count = math.ceil(math.sqrt(self:get_num_animals()))
	end
	if count < 1 then
		return
   end

	if not spawn_locations then
		spawn_locations = self:_find_grass_spawn_points()
	end
	if #spawn_locations < 1 then
		return
   end
   
   local existing_grass = self:_find_all_grass()
   local grass_count = radiant.size(existing_grass)
   count = math.min(count, math.sqrt(#spawn_locations) - grass_count)
   if count < 1 then
      return
   end
	
	local grass_uri = self:_get_spawn_grass_uri()

	local rng = _radiant.math.get_default_rng()
	for i = 1, math.min(#spawn_locations, count) do
		-- try to find an unoccupied space in the bounds; if 5 attempts fail, oh well, don't spawn it
      for attempt = 1, math.min(count, 5) do
         -- remove the location from our list of possibles as we try it, so we don't keep retrying invalid spaces
         -- because it's either already invalid or will become invalid once we spawn grass there
			local location = table.remove(spawn_locations, rng:get_int(1, #spawn_locations)) + Point3(0, 1, 0)
			if self:_is_valid_grass_spawn_location(location) then
				-- we found a spot, spawn some grass
				local grass_entity = radiant.entities.create_entity(grass_uri, {owner = self._entity})
				local random_facing = rng:get_int(0, 3) * 90
				radiant.terrain.place_entity(grass_entity, location, { force_iconic = false, facing = random_facing })
            break
         end
         
         if #spawn_locations < 1 then
            break
         end
      end
      
      if #spawn_locations < 1 then
         break
      end
	end

	self:_setup_grass_spawn_timer()
end

function AceShepherdPastureComponent:_get_grass_uri()
	return radiant.entities.get_json(self).grass_uri or 'stonehearth_ace:terrain:pasture_grass'
end

function AceShepherdPastureComponent:_get_spawn_grass_uri()
	return radiant.entities.get_json(self).spawn_grass_uri or 'stonehearth_ace:terrain:pasture_grass:sprouting'
end

function AceShepherdPastureComponent:_is_valid_grass_spawn_location(location)
	local filter_fn = function(entity)
		return entity ~= self._entity
	end
	return not next(radiant.terrain.get_entities_at_point(location, filter_fn))
end

-- override this base function so it doesn't force animals to be hungry
function AceShepherdPastureComponent:set_feed(feed)
   local previous_feed = self._sv._current_feed
   if self._feed_destroy_listener then
      self._feed_destroy_listener:destroy()
      self._feed_destroy_listener = nil
   end

   self._sv._current_feed = feed
   if self._sv._current_feed then
      self._feed_destroy_listener = radiant.events.listen_once(self._sv._current_feed, 'radiant:entity:pre_destroy', function()
         self:set_feed(nil)
      end)
   end

   if previous_feed ~= self._sv._current_feed then
      radiant.events.trigger_async(self._entity, 'stonehearth:shepherd_pasture:feed_changed', self._entity, self:needs_feed())
   end
end

AceShepherdPastureComponent._ace_old_recalculate_feed_need = ShepherdPastureComponent.recalculate_feed_need
function AceShepherdPastureComponent:recalculate_feed_need()
   if next(self._trough_listeners) then
      radiant.events.trigger_async(self._entity, 'stonehearth_ace:shepherd_pasture:trough_feed_changed', self._entity, self:needs_trough_feed())
   else
      self:_ace_old_recalculate_feed_need()
   end
end

AceShepherdPastureComponent._ace_old_needs_feed = ShepherdPastureComponent.needs_feed
function AceShepherdPastureComponent:needs_feed()
   if next(self._trough_listeners) then
      return false
   else
      return self:_ace_old_needs_feed()
   end
end

function AceShepherdPastureComponent:needs_trough_feed()
   if next(self._trough_listeners) then
      return next(self._empty_troughs) ~= nil
   else
      return false
   end
end

function AceShepherdPastureComponent:get_animal_feed_material()
   local feed_material = self._sv.pasture_type and self._pasture_data[self._sv.pasture_type].feed_material
   if not feed_material then
      return 'fodder_bag'
   else
      return feed_material
   end
end

function AceShepherdPastureComponent:get_pasture_items()
   return self._pasture_items
end

-- gets the first empty trough, or nil
function AceShepherdPastureComponent:get_empty_trough()
   if next(self._trough_listeners) then
      local id = next(self._empty_troughs)
      if id then
         return self._pasture_items[id]
      end
   end
end

function AceShepherdPastureComponent:get_fed_troughs()
   if next(self._fed_troughs) then
      local troughs = {}
      for id, _ in pairs(self._fed_troughs) do
         table.insert(troughs, self._pasture_items[id])
      end
      return troughs
   end
end

function AceShepherdPastureComponent:register_item(item, type)
   local id = item:get_id()
   if not self._pasture_items[id] then
      self._pasture_items[id] = item

      if type == 'trough' then
         self._trough_listeners[id] = radiant.events.listen(item, 'stonehearth_ace:trough:empty_status_changed', function(empty_status)
            self:_on_trough_empty_status_changed(item, empty_status)
         end)
         self:_on_trough_empty_status_changed(item, item:get_component('stonehearth_ace:pasture_item'):is_empty())
      end
   end
end

function AceShepherdPastureComponent:_on_trough_empty_status_changed(item, empty_status)
   local id = item:get_id()
   if empty_status then
      self._empty_troughs[id] = true
      self._fed_troughs[id] = nil
      stonehearth.ai:reconsider_entity(item)
   else
      self._empty_troughs[id] = nil
      self._fed_troughs[id] = true
   end
   self:recalculate_feed_need()
end

function AceShepherdPastureComponent:unregister_item(id)
   self._pasture_items[id] = nil
   self._empty_troughs[id] = nil
   self._fed_troughs[id] = nil
   self:_destroy_trough_listener(id)
end

function AceShepherdPastureComponent:_destroy_trough_listener(id)
   if self._trough_listeners[id] then
      self._trough_listeners[id]:destroy()
      self._trough_listeners[id] = nil
   end
end

function AceShepherdPastureComponent:_collect_strays()
   for id, critter_data in pairs(self._sv.tracked_critters) do
      local critter = critter_data.entity

      if critter and critter:is_valid() then
         local critter_location = radiant.entities.get_world_grid_location(critter)
         if critter_location then -- Critter location can be nil if the critter is an egg that is being moved.
            local region_shape = self._entity:add_component('region_collision_shape'):get_region():get()

            local pasture_location = radiant.entities.get_world_grid_location(self._entity)
            local world_region_shape = region_shape:translated(pasture_location):extruded('y', 0, 10)

            local equipment_component = critter:get_component('stonehearth:equipment')
            local pasture_collar = equipment_component:has_item_type('stonehearth:pasture_equipment:tag')
            local shepherded_animal_component = pasture_collar:get_component('stonehearth:shepherded_animal')

            if not world_region_shape:contains(critter_location) and shepherded_animal_component:can_follow() then
               local town = stonehearth.town:get_town(self._entity)
               local find_stray_task = town:create_task_for_group(
                  'stonehearth:task_groups:herding',
                  'stonehearth:find_stray_animal',
                  {animal = critter, pasture = self._entity})
                     :set_source(critter)
                     :once()
                     :start()

               table.insert(self._added_pasture_tasks, find_stray_task)
            end
         end
      end
   end
end

return AceShepherdPastureComponent
