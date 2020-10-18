local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('trapping')
local TrappingGroundsComponent = require 'stonehearth.components.trapping.trapping_grounds_component'

local AceTrappingGroundsComponent = class()

AceTrappingGroundsComponent._ace_old_load_tuning = TrappingGroundsComponent.load_tuning
function AceTrappingGroundsComponent:load_tuning(json)
   self:_ace_old_load_tuning(json)
   
   self._trap_types = json.trap_types
   self._trappable_animals = json.trappable_animals
   self._seasonal_trappable_animal_weights = json.seasonal_trappable_animal_weights
   self._seasonal_spawn_interval_multipliers = json.seasonal_spawn_interval_multipliers
end

AceTrappingGroundsComponent._ace_old_post_activate = TrappingGroundsComponent.post_activate
function TrappingGroundsComponent:post_activate()
   self:_ace_old_post_activate()

   if self._sv.size then
      self:_setup_wilderness_stuff()
   end

   self._retry_timer_duration = stonehearth.calendar:parse_duration(stonehearth.constants.trapping.UNSUCCESSFUL_SPAWN_RETRY_TIME)
end

AceTrappingGroundsComponent._ace_old_destroy = TrappingGroundsComponent.__user_destroy
function AceTrappingGroundsComponent:destroy()
   if self._wilderness_listener then
      self._wilderness_listener:destroy()
      self._wilderness_listener = nil
   end

   self:_ace_old_destroy()
end

-- this function is only called right after the trapping service sets up the trapping zone (including placing it in the world and setting its size)
-- in order to not have to monkey-patch the trapping service, we'll just use this function to also setup our wilderness stuff
AceTrappingGroundsComponent._ace_old_set_terrain_kind = TrappingGroundsComponent.set_terrain_kind
function AceTrappingGroundsComponent:set_terrain_kind(terrain_kind)
   self:_ace_old_set_terrain_kind(terrain_kind)

   self:_setup_wilderness_stuff()
end

function AceTrappingGroundsComponent:_setup_wilderness_stuff()
   local component = self._entity:get_component('stonehearth_ace:wilderness_signal')
   if not component then
      -- approximate the wilderness values you'd see from the heatmap by extending the signal region
      local extrude_by = stonehearth.constants.wilderness.SAMPLE_RADIUS - 1
      local region = Cube3(Point3.zero, Point3(self._sv.size.x, 1, self._sv.size.z))
      local region_area = region:get_area()
      region = Region3(region:inflated(Point3(extrude_by, extrude_by, extrude_by)))
      component = self._entity:add_component('stonehearth_ace:wilderness_signal')
      component:set_region(region, region_area)
   end

   -- wilderness_value is calculated by the wilderness_signal_component
   if not self._sv.wilderness_value then
      self:_update_wilderness_value(component:get_wilderness_value())
   end
   -- wilderness_multiplier is set through the trapping_grounds_type
   if not self._sv.wilderness_multiplier then
      self:_update_wilderness_multiplier()
   end

   self._wilderness_listener = radiant.events.listen(self._entity, 'stonehearth_ace:wilderness_signal:wilderness_value_changed', self, self._update_wilderness_value)
end

AceTrappingGroundsComponent._ace_old_set_trapping_grounds_type_command = TrappingGroundsComponent.set_trapping_grounds_type_command
function AceTrappingGroundsComponent:set_trapping_grounds_type_command(session, response, trapping_grounds_type)
   if self:_ace_old_set_trapping_grounds_type_command(session, response, trapping_grounds_type) then
      self:_update_wilderness_multiplier()
   end
end

function AceTrappingGroundsComponent:_update_wilderness_multiplier()
   local value = self:get_grounds_type_wilderness_requirement_multiplier()
   if self._sv.wilderness_multiplier ~= value then
      self._sv.wilderness_multiplier = value
      self:_update_wilderness_modifier()
   end
end

function AceTrappingGroundsComponent:_update_wilderness_value(value)
   if value ~= self._sv.wilderness_value then
      self._sv.wilderness_value = value
      self:_update_wilderness_modifier()
   end
end

function AceTrappingGroundsComponent:_update_wilderness_modifier()
   if not self._sv.wilderness_value or not self._sv.wilderness_multiplier then
      self.__saved_variables:mark_changed()
      return
   end

   -- determine the wilderness modifier by looking at the tiers specified in constants
   local value = self._sv.wilderness_value * self._sv.wilderness_multiplier
   self._sv.wilderness_level = self:_get_wilderness_level(value)
   self._sv.wilderness_modifier = self._sv.wilderness_level.spawn_duration_multiplier
   
   -- check if the new spawn duration is shorter than the current timer
   -- if so, we want to restart the timer
   local duration = self:_get_spawn_duration()
   if self._sv.spawn_timer and self._sv.spawn_timer:get_expire_time() - stonehearth.calendar:get_elapsed_time() < duration then
      self:_start_spawn_timer(duration)
   end

   self.__saved_variables:mark_changed()
end

function AceTrappingGroundsComponent:_get_wilderness_level(value)
   for _, level in ipairs(stonehearth.constants.wilderness.LEVELS) do
      if value < level.max then
         return level
      end
   end
end

function AceTrappingGroundsComponent:_get_current_trappable_animals()
   local grounds_type = self._sv.trapping_grounds_type
   return grounds_type and self._trappable_animals[grounds_type]
end

function AceTrappingGroundsComponent:get_grounds_type_wilderness_requirement_multiplier()
   local trappable_animals = self:_get_current_trappable_animals()
   return (trappable_animals and trappable_animals.wilderness_requirement_multiplier) or 1
end

function AceTrappingGroundsComponent:get_grounds_experience_multiplier()
   local trappable_animals = self:_get_current_trappable_animals()
   return trappable_animals and (trappable_animals.experience_multiplier or (1 + (trappable_animals.level_requirement or 1) / 2)) or 1
end

AceTrappingGroundsComponent._ace_old__get_spawn_duration = TrappingGroundsComponent._get_spawn_duration
function AceTrappingGroundsComponent:_get_spawn_duration(successful_spawn)
   if not successful_spawn then
      return self._retry_timer_duration
   end
   
   -- apply modifier from wilderness value
   local season_id = stonehearth.seasons:get_current_season().id
   local seasonal_modifier = self._seasonal_spawn_interval_multipliers[season_id] or 1
   local duration = self:_ace_old__get_spawn_duration() * (self._sv.wilderness_modifier or 1) * seasonal_modifier
   
   return duration
end

AceTrappingGroundsComponent._ace_old_add_trap = TrappingGroundsComponent.add_trap
function AceTrappingGroundsComponent:add_trap(trap)
   self:_ace_old_add_trap(trap)
   trap:add_component('stonehearth_ace:output'):set_parent_output(self._entity)
end

function AceTrappingGroundsComponent:_create_set_trap_task()
   local trap_uri = self._trap_types[self._sv.trapping_grounds_type] or 'stonehearth:trapper:snare_trap'
   local town = stonehearth.town:get_town(self._entity)

   if self._set_trap_task or self._sv.num_traps >= self.max_traps or not town then
      return
   end

   local location = self:_pick_next_trap_location()
   if not location then
      return
   end

   self._set_trap_task = town:create_task_for_group('stonehearth:task_groups:trapping',
                                                    'stonehearth:trapping:set_bait_trap',
                                                    {
                                                       location = location,
                                                       trap_uri = trap_uri,
                                                       trapping_grounds = self._entity
                                                    })
      :set_source(self._entity)
      :once()
      :notify_completed(
         function ()
            self._set_trap_task = nil
            self:_create_set_trap_task() -- keep setting traps serially until done
         end
      )
      :start()
end

function AceTrappingGroundsComponent:_try_spawn()
   if not self._sv.trapping_grounds_type then
      -- don't spawn things if player hasn't set the trapping grounds type yet
      return
   end

   -- must be within the interaction sensor range of the trap
   local max_spawn_distance = 15
   -- won't spawn if threat within this distance of trap or spawn location
   -- TODO: refactor this distance with the avoid_threatening_entities_observer
   local threat_distance = 16

   local successful_spawn = false
   local trap = self:_choose_random_trap_for_critter()

   -- don't retry if there are threats detected. you lose this spawn, do not pass go
   -- place trapping grounds away from trafficed areas if you want to catch things
   if trap and self:_location_is_clear_of_threats(trap, threat_distance) then
      local critter_uri = self:_choose_spawned_critter_type()
      local critter = self:_create_critter(critter_uri)

      local spawn_location
      -- try a few times to find a location to spawn it in case trees or terrain is getting in the way
      for i = 1, 5 do
         spawn_location = self:_get_spawn_location(trap, max_spawn_distance, critter)
         if spawn_location then
            break
         end
      end

      if spawn_location and self:_location_is_clear_of_threats(spawn_location, threat_distance) then
         radiant.terrain.place_entity(critter, spawn_location)
         self:_create_try_bait_task(critter, trap)
         successful_spawn = true
         -- BUG: saving the game before untrapped critters despawn leaves them in the world
      else
         radiant.entities.destroy_entity(critter)
      end
   end

   local duration = self:_get_spawn_duration(successful_spawn)
   self:_start_spawn_timer(duration)
end

-- also ignore any trappers as QoL
AceTrappingGroundsComponent._ace_old__is_threatening_to_critter = TrappingGroundsComponent._is_threatening_to_critter
function AceTrappingGroundsComponent:_is_threatening_to_critter(other_entity)
   local job = other_entity:get_component('stonehearth:job')
   if job then
      local curr_job_controller = job:get_curr_job_controller()
      if curr_job_controller and curr_job_controller:is_trapper() then
         return false
      end
   end

   return self:_ace_old__is_threatening_to_critter(other_entity)
end

function AceTrappingGroundsComponent:_choose_spawned_critter_type()
   local trapping_grounds_type = self._sv.trapping_grounds_type
   local weights = radiant.shallow_copy(self.trappable_animal_weights[trapping_grounds_type])
   local season_id = stonehearth.seasons:get_current_season().id
   local all_override_weights = self._seasonal_trappable_animal_weights[season_id] or {}
   local override_weights = all_override_weights[trapping_grounds_type] or {}

   local weighted_set = WeightedSet(rng)

   for uri, weight in pairs(override_weights) do
      weights[uri] = weight
   end
   for uri, weight in pairs(weights) do
      weighted_set:add(uri, weight)
   end

   local uri = weighted_set:choose_random()
   return uri
end

return AceTrappingGroundsComponent
