local EvolveComponent = require 'stonehearth.components.evolve.evolve_component'
local AceEvolveComponent = class()

function AceEvolveComponent:initialize()
   self._sv.evolve_timer = nil
end

function AceEvolveComponent:activate()
   self._evolve_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:evolve_data')

   local entity_forms = self._entity:get_component('stonehearth:entity_forms')
   if entity_forms then
      -- If we have an entity forms component, wait until we are actually in the world before starting the evolve component
      self._added_to_world_trace = radiant.events.listen_once(self._entity, 'stonehearth:on_added_to_world', function()
            self:_start()
            self._added_to_world_trace = nil
         end)
   else
      self:_start()
   end
   
   self._growth_rate_listener = radiant.events.listen(radiant, 'stonehearth:growth_rate_may_have_changed', function()
         self:_recalculate_duration()
      end)
end

function AceEvolveComponent:_start()
   if not self._sv.evolve_timer then
      self:_start_evolve_timer()
   else
      if self._sv.evolve_timer then
         self._sv.evolve_timer:bind(function()
               self:evolve()
            end)
      end
   end
end

function AceEvolveComponent:destroy()
   if self._added_to_world_trace then
      self._added_to_world_trace:destroy()
      self._added_to_world_trace = nil
   end
   if self._growth_rate_listener then
      self._growth_rate_listener:destroy()
      self._growth_rate_listener = nil
   end

   self:_stop_evolve_timer()
end

function AceEvolveComponent:_create_water_listener()
	-- determine the "reach" of water detection from json; otherwise just expand 1 outwards and downwards from destination region

	self._entity:add_component('stonehearth_ace:water_signal')
	self._water_listener = radiant.events.listen(self._entity, 'stonehearth_ace:water_signal:water_volume_changed', self, self._on_water_exists_changed)
end

function AceEvolveComponent:_destroy_water_listener()
	if self._water_listener then
		self._water_listener:destroy()
		self._water_listener = nil
	end
end

function AceEvolveComponent:evolve()
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
   --Create the evolved entity and put it on the ground
   local evolved_form = radiant.entities.create_entity(evolved_form_uri, { owner = self._entity})
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
   
   local duration = self:_calculate_growth_period(stonehearth.calendar:parse_duration(self._evolve_data.evolve_time))
   self._sv.evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", duration, radiant.bind(self, 'evolve'))

   self.__saved_variables:mark_changed()
end

function AceEvolveComponent:_recalculate_duration()
   if self._sv.evolve_timer then
      local old_duration = self._sv.evolve_timer:get_duration()
      local old_expire_time = self._sv.evolve_timer:get_expire_time()
      local old_start_time = old_expire_time - old_duration
      local evolve_period = stonehearth.calendar:parse_duration(self._evolve_data.evolve_time)
      local time_remaining = old_start_time + evolve_period - stonehearth.calendar:get_elapsed_time()
      if time_remaining > 0 then
         local scaled_time_remaining = self:_calculate_growth_period(time_remaining)
         self._sv.evolve_timer:destroy()
         self._sv.evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", scaled_time_remaining, radiant.bind(self, 'evolve'))
      else
         self:evolve()
      end
   end
end

function AceEvolveComponent:_calculate_growth_period(evolve_time)
   local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
   if catalog_data.category == 'seed' or catalog_data.category == 'plants' then
      evolve_time = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), evolve_time)
   end

   return evolve_time
end

function AceEvolveComponent:_stop_evolve_timer()
   if self._sv.evolve_timer then
      self._sv.evolve_timer:destroy()
      self._sv.evolve_timer = nil
   end

   self.__saved_variables:mark_changed()
end

return AceEvolveComponent
