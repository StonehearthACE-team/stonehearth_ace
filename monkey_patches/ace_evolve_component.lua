local transform_lib = require 'stonehearth_ace.lib.transform.transform_lib'
local log = radiant.log.create_logger('evolve')

local EvolveComponent = require 'stonehearth.components.evolve.evolve_component'
local AceEvolveComponent = class()

AceEvolveComponent._ace_old_restore = EvolveComponent.restore
function AceEvolveComponent:restore()
   -- if we're restoring an entity that should be stunted, remove this component immediately
   local properties = self._entity:get_component('stonehearth:properties')
   if properties and properties:has_property('stonehearth_ace:stunted') then
      self._entity:remove_component(self.__saved_variables:get_controller_name())
      return
   end

   if self._sv.evolve_timer then
      self._sv._evolve_timer = self._sv.evolve_timer
      self._sv.evolve_timer = nil
   end
   
   self._sv.last_calculated_water_volume = nil
   self._sv._local_water_modifier = nil
   self._sv._water_level = nil
   
   if self._ace_old_restore then
      self:_ace_old_restore()
   end
end

--AceEvolveComponent._ace_old_activate = EvolveComponent.activate
function AceEvolveComponent:activate()
   if not self._sv._current_growth_recalculate_progress then
      self._sv._current_growth_recalculate_progress = 0
   end

   self._evolve_time_multipliers = {}
   
   self._evolve_data = radiant.entities.get_entity_data(self._entity, 'stonehearth:evolve_data')

   -- had to insert this section, so can't just call _ace_old_activate
   if self._evolve_data then
      if self._evolve_data.biomes then
         -- if there are special biome modifiers to be applied, make sure we do so
         local biome_uri = stonehearth.world_generation:get_biome_alias()
         local modifiers = self._evolve_data.biomes[biome_uri]
         if modifiers then
            self:_apply_modifiers('biome', modifiers)
         end
      end
      self:_create_listeners()
   end

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

function AceEvolveComponent:post_activate()
   -- if it doesn't have any evolve_data, try to remove the component because it should no longer be active
   if not self._evolve_data then
      self._entity:remove_component('stonehearth:evolve')
   else
      self:_create_listeners()
   end

   -- if we had an evolve water signal for this entity, destroy it
   -- if that was the only water signal for it, get rid of the component
   local water_signal_comp = self._entity:get_component('stonehearth_ace:water_signal')
   if water_signal_comp then
      water_signal_comp:remove_signal('evolve')
      if not water_signal_comp:has_signal() then
         self._entity:remove_component('stonehearth_ace:water_signal')
      end
   end
end

AceEvolveComponent._ace_old_destroy = EvolveComponent.__user_destroy
function AceEvolveComponent:destroy()
   self:_ace_old_destroy()
   self:_destroy_listeners()
end

function AceEvolveComponent:_create_listeners()
   if self._evolve_data.seasons then
      self._season_change_listener = radiant.events.listen(stonehearth.seasons, 'stonehearth:seasons:changed', function()
         self:_check_season()
         self:_recalculate_duration()
      end)
      self:_check_season()
   end
end

function AceEvolveComponent:_destroy_listeners()
   if self._season_change_listener then
      self._season_change_listener:destroy()
      self._season_change_listener = nil
   end
end

function AceEvolveComponent:_check_season()
   local season = stonehearth.seasons:get_current_season()
   local modifiers = season and self._evolve_data.seasons[season.id]
   self:_apply_modifiers('season', modifiers)
end

function AceEvolveComponent:_apply_modifiers(key, modifiers)
   self._evolve_time_multipliers[key] = modifiers and modifiers.evolve_time_multiplier or 1
end

-- override the original to prepend evolve_timer with an underscore for performance reasons
function AceEvolveComponent:_start()
   if not self._sv._evolve_timer then
      self:_start_evolve_timer()
   else
      if self._sv._evolve_timer then
         self._sv._evolve_timer:bind(function()
               self:evolve()
            end)
      end
   end
end

-- override the original to prepend evolve_timer with an underscore for performance reasons
function AceEvolveComponent:_stop_evolve_timer()
   if self._sv._evolve_timer then
      self._sv._evolve_timer:destroy()
      self._sv._evolve_timer = nil
   end

   --self.__saved_variables:mark_changed()
end

function AceEvolveComponent:_get_transform_options()
   local transform_comp = self._entity:get_component('stonehearth_ace:transform')
   return transform_comp and transform_comp:get_option_overrides() or {}
end

function AceEvolveComponent:evolve()
   self:_stop_evolve_timer()

   local transform_options = self:_get_transform_options()
   local options = {
      check_script = self._evolve_data.evolve_check_script,
      transform_effect = self._evolve_data.evolve_effect,
      auto_harvest = self._evolve_data.auto_harvest,
      transform_script = self._evolve_data.evolve_script,
      kill_entity = self._evolve_data.kill_entity,
      destroy_entity = self._evolve_data.destroy_entity,
      transform_event = function(evolved_form)
         radiant.events.trigger(self._entity, 'stonehearth:on_evolved', {entity = self._entity, evolved_form = evolved_form})
      end
   }
   radiant.util.merge_into_table(transform_options, options)
   local transformed = transform_lib.transform(self._entity, 'stonehearth:evolve', self._evolve_data.next_stage, transform_options)

   if transformed == false then
      self:_start_evolve_timer()
      return
   end

   return transformed
end

function AceEvolveComponent:_start_evolve_timer()
	self:_stop_evolve_timer()
   
   if self._evolve_data then
      local duration = self:_calculate_growth_period()
      self._sv._evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", duration, radiant.bind(self, 'evolve'))

      --self.__saved_variables:mark_changed()
   end
end

function AceEvolveComponent:_recalculate_duration()
	if self._sv._evolve_timer then
		local old_duration = self._sv._evolve_timer:get_duration()
		local old_expire_time = self._sv._evolve_timer:get_expire_time()
		local old_start_time = old_expire_time - old_duration
		local evolve_period = self:_get_base_growth_period()
		
		local old_progress = self:_get_current_growth_recalculate_progress()
		local new_progress = (1 - old_progress) * (stonehearth.calendar:get_elapsed_time() - old_start_time) / old_duration
		self._sv._current_growth_recalculate_progress = old_progress + new_progress
		local time_remaining = math.max(0, evolve_period * (1 - self._sv._current_growth_recalculate_progress))
		if time_remaining > 0 then
			local scaled_time_remaining = self:_calculate_growth_period(time_remaining)
			self._sv._evolve_timer:destroy()
			self._sv._evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", scaled_time_remaining, radiant.bind(self, 'evolve'))
		else
			self:evolve()
		end
	end
end

function AceEvolveComponent:_get_current_growth_recalculate_progress()
	return self._sv._current_growth_recalculate_progress
end

function AceEvolveComponent:_get_base_growth_period()
	local growth_period = stonehearth.calendar:parse_duration(self._evolve_data.evolve_time)
	return growth_period
end

function AceEvolveComponent:_calculate_growth_period(evolve_time)
	if not evolve_time then
		evolve_time = self:_get_base_growth_period()
	end
	
	local catalog_data = stonehearth.catalog:get_catalog_data(self._entity:get_uri())
	if catalog_data.category == 'seed' or catalog_data.category == 'plants' then
		evolve_time = stonehearth.town:calculate_growth_period(self._entity:get_player_id(), evolve_time)
   end
   
   for _, multiplier in pairs(self._evolve_time_multipliers) do
      evolve_time = evolve_time * multiplier
   end

	return evolve_time
end

return AceEvolveComponent
