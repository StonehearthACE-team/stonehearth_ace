local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()

local item_quality_lib = require 'stonehearth_ace.lib.item_quality.item_quality_lib'
local log = radiant.log.create_logger('evolve')

local EvolveComponent = require 'stonehearth.components.evolve.evolve_component'
local AceEvolveComponent = class()

local RECALCULATE_THRESHOLD = 0.5

AceEvolveComponent._ace_old_restore = EvolveComponent.restore
function AceEvolveComponent:restore()
   self._sv._evolve_timer = self._sv.evolve_timer
   self._sv.evolve_timer = nil
   self._sv.last_calculated_water_volume = nil
   self._sv._local_water_modifier = nil
   self._sv._water_level = nil
   
   if self._ace_old_restore then
      self:_ace_old_restore()
   end
end

AceEvolveComponent._ace_old_activate = EvolveComponent.activate
function AceEvolveComponent:activate()
   if not self._sv._current_growth_recalculate_progress then
      self._sv._current_growth_recalculate_progress = 0
   end
   
   self:_ace_old_activate()   -- need to call this before other functions because it sets self._evolve_data
   self:_create_request_listeners()
end

function AceEvolveComponent:post_activate()
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

AceEvolveComponent._ace_old_destroy = EvolveComponent.destroy
function AceEvolveComponent:destroy()
   self:_ace_old_destroy()
   
   self:_destroy_effect()
   self:_destroy_request_listeners()
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
function EvolveComponent:_stop_evolve_timer()
   if self._sv._evolve_timer then
      self._sv._evolve_timer:destroy()
      self._sv._evolve_timer = nil
   end

   self.__saved_variables:mark_changed()
end

function AceEvolveComponent:_create_request_listeners()
   self:_destroy_request_listeners()
   
   if self._evolve_data.request_action then
      if self._evolve_data.auto_request then
         self._added_to_world_listener = self._entity:add_component('mob'):trace_parent('evolve entity added or removed')
            :on_changed(function(parent)
               if parent then
                  self:request_evolve(self._entity:get_player_id())
               end
            end)
      end

      --[[
      self._task_requested_listener = radiant.events.listen(self._entity, 'stonehearth_ace:task_tracker:task_requested', function()
         self:_refresh_attention_effect()
      end)

      self._task_canceled_listener = radiant.events.listen(self._entity, 'stonehearth_ace:task_tracker:task_canceled', function()
         self:_refresh_attention_effect()
      end)

      self:_refresh_attention_effect()
      ]]
   end
end

function AceEvolveComponent:_destroy_request_listeners()
   if self._added_to_world_listener then
      self._added_to_world_listener:destroy()
      self._added_to_world_listener = nil
   end

   --[[
   if self._task_requested_listener then
      self._task_requested_listener:destroy()
      self._task_requested_listener = nil
   end

   if self._task_canceled_listener then
      self._task_canceled_listener:destroy()
      self._task_canceled_listener = nil
   end
   ]]
end

AceEvolveComponent._ace_old_evolve = EvolveComponent.evolve
function AceEvolveComponent:evolve()
   if self._evolve_data.evolve_check_script then
      local script = radiant.mods.require(self._evolve_data.evolve_check_script)
      if script and not script.should_evolve(self) then
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

   local evolved_form

   if evolved_form_uri then
      --Create the evolved entity and put it on the ground
      evolved_form = radiant.entities.create_entity(evolved_form_uri, { owner = self._entity})
      
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

      local owner_component = self._entity:get_component('stonehearth:ownable_object')
      local owner = owner_component and owner_component:get_owner()
      if owner then
         local evolved_owner_component = evolved_form:get_component('stonehearth:ownable_object')
         if evolved_owner_component then
            -- need to remove the original's owner so that destroying it later doesn't mess things up with the new entity's ownership
            owner_component:set_owner(nil)
            evolved_owner_component:set_owner(owner)
         end
      end

      local unit_info = self._entity:get_component('stonehearth:unit_info')
      local custom_name = unit_info and unit_info:get_custom_name()
      if custom_name then
         local evolved_unit_info = evolved_form:get_component('stonehearth:unit_info')
         if evolved_unit_info then
            evolved_unit_info:set_custom_name(custom_name)
         end
      end

      local evolved_form_data = radiant.entities.get_entity_data(evolved_form, 'stonehearth:evolve_data')
      if evolved_form_data then
         -- Ensure the evolved form also has the evolve component if it will evolve
         -- but first check if it should get "stunted"
         if not evolved_form_data.stunted_chance or rng:get_real(0, 1) > evolved_form_data.stunted_chance then
            evolved_form:add_component('stonehearth:evolve')
         end
      end

      radiant.terrain.place_entity_at_exact_location(evolved_form, location, { force_iconic = false, facing = facing } )

      local evolve_effect = self._evolve_data.evolve_effect
      if evolve_effect then
         radiant.effects.run_effect(evolved_form, evolve_effect)
      end

      if self._evolve_data.auto_harvest then
         local renewable_resource_node = evolved_form:get_component('stonehearth:renewable_resource_node')
         local resource_node = evolved_form:get_component('stonehearth:resource_node')

         if renewable_resource_node and renewable_resource_node:is_harvestable() then
            renewable_resource_node:request_harvest(self._entity:get_player_id())
         elseif resource_node then
            resource_node:request_harvest(self._entity:get_player_id())
         end
      end
   end

   if self._evolve_data.evolve_script then
      local script = radiant.mods.require(self._evolve_data.evolve_script)
      script.evolve(self._entity, evolved_form)
   end

   radiant.events.trigger(self._entity, 'stonehearth:on_evolved', {entity = self._entity, evolved_form = evolved_form})

   -- option to kill on evolve instead of destroying (e.g., if you need to have it drop loot or trigger the killed event)
   if self._evolve_data.kill_entity then
      radiant.entities.kill_entity(self._entity)
   elseif not self._evolve_data.destroy_entity == false then
      radiant.entities.destroy_entity(self._entity)
   end

   return evolved_form
end

function AceEvolveComponent:_start_evolve_timer()
	self:_stop_evolve_timer()
   
   -- if there's an evolve_time in the evolve_data (standard), make a timer
   -- if there's an evolve_command in it instead, add that command
   if self._evolve_data.evolve_time then
      local duration = self:_calculate_growth_period()
      self._sv._evolve_timer = stonehearth.calendar:set_persistent_timer("EvolveComponent renew", duration, radiant.bind(self, 'evolve'))
   elseif self._evolve_data.evolve_command then
      local command_comp = self._entity:add_component('stonehearth:commands')
      if not command_comp:has_command(self._evolve_data.evolve_command) then
         command_comp:add_command(self._evolve_data.evolve_command)
      end
   end

	self.__saved_variables:mark_changed()
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

	return evolve_time
end

function AceEvolveComponent:_set_quality(item, source)
   item_quality_lib.copy_quality(source, item)
end

function AceEvolveComponent:request_evolve(player_id)
   local data = self._evolve_data
   if not data then
      return false
   end

   -- probably shouldn't have to check this because the command should already filter with "visible_to_all_players"
   if data.check_owner and not radiant.entities.is_neutral_animal(self._entity:get_player_id())
      and radiant.entities.is_owned_by_another_player(self._entity, player_id) then
      return false
   end

   if data.request_action then
      local task_tracker_component = self._entity:add_component('stonehearth:task_tracker')
      local was_requested = task_tracker_component:is_activity_requested(data.request_action)

      task_tracker_component:cancel_current_task(false) -- cancel current task first and force the evolve request

      if was_requested then
         return false -- If someone had already requested to evolve, just cancel the request and exit out
      end

      local category = 'evolve'  --data.category or 
      local success = task_tracker_component:request_task(player_id, category, data.request_action, data.request_action_overlay_effect)
      return success
   else
      self:perform_evolve(true)
      return true
   end
end

-- this function gets called directly by request_evolve unless a request_action is specified
-- if such an action is specified, this function should be called as part of that AI action
function AceEvolveComponent:perform_evolve(use_finish_cb)
   local data = self._evolve_data
   if not data then
      return false
   end

   if data.evolving_effect then
      self:_run_effect(data.evolving_effect, use_finish_cb)
   elseif not data.evolving_worker_effect then
      self:evolve()
   end
end

function AceEvolveComponent:_run_effect(effect, use_finish_cb)
   if not self._effect then
      self._effect = radiant.effects.run_effect(self._entity, effect)
      if use_finish_cb then
         self._effect:set_finished_cb(function()
               self:_destroy_effect()
               self:evolve()
            end)
      end
   end
end

function AceEvolveComponent:_destroy_effect()
   if self._effect then
      self._effect:set_finished_cb(nil)
                  :stop()
      self._effect = nil
   end
end

--[[
function AceEvolveComponent:_refresh_attention_effect()
   local data = self._evolve_data
   if not data or not data.request_action then
      return
   end
   
   local task_tracker_component = self._entity:get_component('stonehearth:task_tracker')
   local needs_effect = not task_tracker_component or not task_tracker_component:has_any_task()
   local has_effect = self._attention_effect ~= nil
   if needs_effect ~= has_effect then
      if needs_effect then
         self._attention_effect = radiant.effects.run_effect(self._entity, 'stonehearth_ace:effects:evolve_action_available_overlay_effect',
               nil, nil, { playerColor = radiant.entities.get_player_color(self._entity) })
      else
         self._attention_effect:stop()
         self._attention_effect = nil
      end
   end
end
]]

return AceEvolveComponent
