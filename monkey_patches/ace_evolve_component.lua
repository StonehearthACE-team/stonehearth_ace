local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'

local EvolveComponent = require 'stonehearth.components.evolve.evolve_component'
local AceEvolveComponent = class()

local RECALCULATE_THRESHOLD = 0.5

AceEvolveComponent._old_initialize = EvolveComponent.initialize
function AceEvolveComponent:initialize()
	self:_old_initialize()

	self._sv.local_water_modifier = 1
	-- would need to set up a child entity with its own water component for detecting flooding in a smaller region
	--self._sv.is_flooded = false
   self._sv.current_growth_recalculate_progress = 0
   
	self.__saved_variables:mark_changed()
end

AceEvolveComponent._old_activate = EvolveComponent.activate
function AceEvolveComponent:activate()
	self:_old_activate()

   -- allow for additional checks for whether evolve should happen by specifying a script in the json
   self._json = radiant.entities.get_json(self) or {}
   self._sv.evolve_check_script = self._json.evolve_check_script
   self._preferred_climate = self._json.preferred_climate
   -- determine the "reach" of water detection from json; otherwise just expand 1 outwards and downwards from collision region
   self._water_reach = self._json.water_reach or 1
end

function AceEvolveComponent:post_activate()
	-- we don't care about water for animals, only for plants
	local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
	if catalog_data.category == 'seed' or catalog_data.category == 'plants' then
		self._water_affinity = stonehearth.town:get_water_affinity_table(self._preferred_climate)
		
		self:_create_water_signal()
   end
end

function AceEvolveComponent:set_check_evolve_script(path)
   self._sv.evolve_check_script = path
   self.__saved_variables:mark_changed()
end

function AceEvolveComponent:_create_water_signal()
	local reach = self._water_reach
	local region = self._entity:get_component('region_collision_shape')
	-- if there's no collision region, oh well, guess we're not creating a listener
   if region then
      region = region:get_region():get()
   else
      region = Region3(Cube3(Point3.zero))
	end

	self._water_region = region
						:extruded('x', reach, reach)
						:extruded('z', reach, reach)
                  :extruded('y', reach, 0)
   
   local water_component = self._entity:add_component('stonehearth_ace:water_signal')
   self._water_signal = water_component:set_signal('evolve', self._water_region, {'water_volume'}, function(changes) self:_on_water_signal_changed(changes) end)
end

function AceEvolveComponent:_on_water_signal_changed(changes)
   local volume = changes.water_volume.value
   if not volume then
      return
   end

	-- water level is a ratio of volume to "normal ideal volume for this plant"
	-- we consider the normal ideal ratio for a plant to be 1 water per square root of its detection area
	local area = self._water_region:get_area()
	--local ideal_ratio = 1 / math.sqrt(area)
	--local this_ratio = volume / area
	--self._sv._water_level = this_ratio / ideal_ratio
	-- the above simplifies to this:
   self._sv._water_level = volume / math.sqrt(area)
   
   -- if the water level only changed by a tiny bit, we don't want to have to recalculate timers
   -- once the change meets a particular threshold, go ahead and propogate
   local last_calculated = self._sv.last_calculated_water_volume
   if last_calculated and math.abs(last_calculated - volume) < RECALCULATE_THRESHOLD then
      self.__saved_variables:mark_changed()
      return
   end

   self._sv.last_calculated_water_volume = volume
	
	local best_affinity = {min_water = -1, period_multiplier = 1}
	for _, affinity in ipairs(self._water_affinity) do
		if self._sv._water_level >= affinity.min_water and affinity.min_water > best_affinity.min_water then
			best_affinity = affinity
		end
	end

	local multiplier = best_affinity.period_multiplier
	local prev_modifier = self._sv.local_water_modifier
	if multiplier ~= prev_modifier then
		self._sv.local_water_modifier = multiplier
		self:_recalculate_duration()
	end

	self.__saved_variables:mark_changed()
end

-- returns the best affinity and then the next one so you can see the range until it would apply (and its effect)
function AceEvolveComponent:get_best_water_level()
	if not next(self._water_affinity) then
		return nil
	end

	local best_affinity = self._water_affinity[1]
	local next_affinity = self._water_affinity[2]
	for i = 2, self._water_affinity.n do
		local affinity = self._water_affinity[i]
		if (self._sv._water_level or 0) >= affinity.min_water and affinity.min_water > best_affinity.min_water then
			best_affinity = affinity
			next_affinity = self._water_affinity[i + 1]
		end
	end

	return best_affinity, next_affinity
end

AceEvolveComponent._old_evolve = EvolveComponent.evolve
function AceEvolveComponent:evolve()
   if self._sv.evolve_check_script then
      local script = radiant.mods.require(self._sv.evolve_check_script)
      if script and not script._should_evolve(self) then
         self:_start_evolve_timer()
         return
      end
   end

   -- Paul: simplest to just copy in all the old evolve code here because
   -- we need to set item quality on the new entity before destroying this one

   self:_stop_evolve_timer()

   -- if we've been suspended, just restart the timer
   if radiant.entities.is_entity_suspended(self._entity) then
      self:_start_evolve_timer()
      return
   end

   local location = radiant.entities.get_world_grid_location(self._entity)
   if not location then
      return
   end
   local facing = radiant.entities.get_facing(self._entity)

   local evolved_form_uri = self._evolve_data.next_stage
   if type(evolved_form_uri) == 'table' then
      evolved_form_uri = evolved_form_uri[rng:get_int(1, #evolved_form_uri)]
   end   
   --Create the evolved entity and put it on the ground
   local evolved_form = radiant.entities.create_entity(evolved_form_uri, { owner = self._entity})
   
   -- Paul: this is the only line of code being inserted into the base evolve function
   self:_set_quality(evolved_form, self._entity)

   radiant.entities.set_player_id(evolved_form, self._entity)

   -- Have to remove entity because it can collide with evolved form
   radiant.terrain.remove_entity(self._entity)
   if not radiant.terrain.is_standable(evolved_form, location) then
      -- If cannot evolve because the evolved form will not fit in the current location, set a timer to try again.
      radiant.terrain.place_entity_at_exact_location(self._entity, location, { force_iconic = false, facing = facing })
      radiant.entities.destroy_entity(evolved_form)
      --TODO(yshan) maybe add tuning for specific retry to grow time
      self:_start_evolve_timer()
      return
   end

   local evolved_form_data = radiant.entities.get_entity_data(evolved_form, 'stonehearth:evolve_data')
   if evolved_form_data and evolved_form_data.next_stage then
      -- Ensure the evolved form also has the evolve component if it will evolve
      evolved_form:add_component('stonehearth:evolve')
   end

   radiant.terrain.place_entity_at_exact_location(evolved_form, location, { force_iconic = false, facing = facing } )

   local evolve_effect = self._evolve_data.evolve_effect
   if evolve_effect then
      radiant.effects.run_effect(evolved_form, evolve_effect)
   end

   radiant.events.trigger(self._entity, 'stonehearth:on_evolved', {entity = self._entity, evolved_form = evolved_form})
   radiant.entities.destroy_entity(self._entity)
end

function AceEvolveComponent:_start_evolve_timer()
	self:_stop_evolve_timer()
   
	local duration = self:_calculate_growth_period()
	self._sv.evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", duration, radiant.bind(self, 'evolve'))

	self.__saved_variables:mark_changed()
end

function AceEvolveComponent:_recalculate_duration()
	if self._sv.evolve_timer then
		local old_duration = self._sv.evolve_timer:get_duration()
		local old_expire_time = self._sv.evolve_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration
		local evolve_period = self:_get_base_growth_period()
		
		local old_progress = self:_get_current_growth_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv.current_growth_recalculate_progress = old_progress + new_progress
		local time_remaining = math.max(0, evolve_period * (1 - self._sv.current_growth_recalculate_progress))
		if time_remaining > 0 then
			local scaled_time_remaining = self:_calculate_growth_period(time_remaining)
			self._sv.evolve_timer:destroy()
			self._sv.evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", scaled_time_remaining, radiant.bind(self, 'evolve'))
		else
			self:evolve()
		end
	end
end

function AceEvolveComponent:_get_current_growth_recalculate_progress()
	return self._sv.current_growth_recalculate_progress or 0
end

function AceEvolveComponent:_get_base_growth_period()
	local growth_period = stonehearth.calendar:parse_duration(self._evolve_data.evolve_time)
	--if self._is_in_preferred_season == false then  -- Nil is equivalent to preferred.
	--	growth_period = growth_period * stonehearth.constants.farming.NONPREFERRED_SEASON_GROWTH_TIME_MULTIPLIER
	--end
	return growth_period
end

function AceEvolveComponent:_calculate_growth_period(evolve_time)
	if not evolve_time then
		evolve_time = self:_get_base_growth_period()
	end
	
	local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
	if catalog_data.category == 'seed' or catalog_data.category == 'plants' then
		evolve_time = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), evolve_time) * (self._sv.local_water_modifier or 1)
		--if self._sv.is_flooded then
		--	evolve_time = evolve_time * self._flood_period_multiplier
		--end
	end

	return evolve_time
end

function AceEvolveComponent:_set_quality(item, source)
   item_quality_lib.copy_quality(source, item, {override_allow_variable_quality = true})
end

return AceEvolveComponent
