--[[
   contains a lot of the core functionality that was previously in the water_pump component
   but made more flexible
]]

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('water_sponge')

local WaterSpongeComponent = class()

local FAIL_IGNORE_COUNT = 10

function WaterSpongeComponent:initialize()
   self._json = radiant.entities.get_json(self)

   self._input_rate = self._json.input_rate or 0
   self._output_rate = self._json.output_rate or 0
   self._create_water = self._json.create_water
   self._destroy_water = self._json.destroy_water
   -- if the sponge is in absorb mode, disable once it's at full capacity; if in release mode, disable once it's empty
   self._auto_disable_on_full_or_empty = self._json.auto_disable_on_full_or_empty
   self._input_fail_ignores = 0
   self._output_fail_ignores = 0
   self._prev_input_water_entity = nil
   self._prev_output_water_entity = nil

   self._effects = {}
end

function WaterSpongeComponent:create()
   self._is_create = true

   if self._json.input_location then
      self._sv._input_location = radiant.util.to_point3(self._json.input_location)
   end
   if self._json.input_region then
      self._sv._input_region = radiant.util.to_region3(self._json.input_region)
   end
   if self._json.output_location then
      self._sv._output_location = radiant.util.to_point3(self._json.output_location)
   end

   self._sv.input_enabled = self._json.input_enabled ~= false
   self._sv.output_enabled = self._json.output_enabled ~= false
end

function WaterSpongeComponent:post_activate()
   self._wetting_volume = stonehearth.constants.hydrology.WETTING_VOLUME
   self._container = self._entity:get_component('stonehearth_ace:container')

   --Trace the parent to figure out if it's added or not:
	self._parent_trace = self._entity:add_component('mob'):trace_parent('water sponge added or removed')
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world
               self:_shutdown()
            else
               --we were just added to the world
               self:_startup()
            end
         end)

   self._entity:remove_component('stonehearth:wet_stone')

   self:_startup()
end

function WaterSpongeComponent:destroy()
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   self:_stop_effects()
end

function WaterSpongeComponent:_ensure_effect(condition, name, ...)
   if condition then
      self:_start_effect(name, self._json.effects[name], ...)
   else
      self:_stop_effect(name)
   end
end

function WaterSpongeComponent:_start_effect(name, effect, location, location_is_relative)
   if not self._effects[name] then
      local entity = self._entity
      if location then
         -- if this effect should happen at a separate location, make a proxy entity there
         entity = radiant.entities.create_entity('stonehearth:object:transient', { debug_text = name .. ' effect anchor' })
         
         -- assume the location is relative unless otherwise specified (e.g., input/output location)
         if location_is_relative ~= false then
            location = radiant.entities.get_world_grid_location(self._entity) + location:rotated(radiant.entities.get_facing(self._entity))
         end

         radiant.terrain.place_entity_at_exact_location(proxy, location)
      end

      self._effects[name] = radiant.effects.run_effect(entity, effect)
         :set_cleanup_on_finish(false)
   end
end

function WaterSpongeComponent:_stop_effect(name)
   if self._effects[name] then
      self._effects[name]:stop()
      self._effects[name] = nil
   end
end

function WaterSpongeComponent:_stop_effects()
   for _, effect in pairs(self._effects) do
      effect:stop()
   end
   self._effects = {}
end

function WaterSpongeComponent:_startup()
	local location = radiant.entities.get_world_grid_location(self._entity)
	if not location then
		return
	end

   stonehearth.hydrology:unregister_water_processor(self._entity:get_id(), self)
   stonehearth.hydrology:register_water_processor(self._entity:get_id(), self, location.y)
   self:_update_commands()
   self:_update_effects()
end

function WaterSpongeComponent:_shutdown()
   stonehearth.hydrology:unregister_water_processor(self._entity:get_id(), self)
   self:_update_effects()
end

function WaterSpongeComponent:get_input_rate()
   return self._sv._input_rate_override or self._input_rate
end

function WaterSpongeComponent:set_input_rate(rate)
   self._sv._input_rate_override = rate
end

function WaterSpongeComponent:get_output_rate()
   return self._sv._output_rate_override or self._output_rate
end

function WaterSpongeComponent:set_output_rate(rate)
   self._sv._output_rate_override = rate
end

function WaterSpongeComponent:get_input_location()
   return self._sv._input_location
end

function WaterSpongeComponent:set_input_location(location)
   self._sv._input_location = location
end

function WaterSpongeComponent:get_input_region()
   return self._sv._input_region
end

function WaterSpongeComponent:set_input_region(region)
   self._sv._input_region = region
end

function WaterSpongeComponent:get_output_location()
   return self._sv._output_location, self._sv._output_origin
end

function WaterSpongeComponent:set_output_location(location, origin)
   self._sv._output_location = location
   self._sv._output_origin = origin
end

function WaterSpongeComponent:set_enabled(input, output)
   self._sv.input_enabled = input
   self._sv.output_enabled = output
   self.__saved_variables:mark_changed()

   self:_update_commands()
   self:_update_effects()
end

function WaterSpongeComponent:is_flow_enabled()
   return self._sv.input_enabled and self._sv.output_enabled
end

function WaterSpongeComponent:is_flow_disabled()
   return not self._sv.input_enabled and not self._sv.output_enabled
end

function WaterSpongeComponent:reset_processed_this_tick()
   self._processed_this_tick = false
end

function WaterSpongeComponent:on_tick_water_processor()
   if self._processed_this_tick then
      return
   end
   self._processed_this_tick = true

	if not self._sv.input_enabled and not self._sv.output_enabled then
		return
	end

	local location = radiant.entities.get_world_grid_location(self._entity)
	if not location then
		return
   end

   -- first try outputting what we have
   -- a pipe/pump/sponge will output from its container; a well/wet-stone will simply create water and not have a container

   if self._output_fail_ignores > 0 then
      self._output_fail_ignores = self._output_fail_ignores - 1
   elseif self._sv.output_enabled then
      local output_rate = self:get_output_rate()
      if output_rate > 0 then
         local output_location = self._sv._output_location
         if output_location then
            output_location = radiant.entities.local_to_world(output_location, self._entity)

            local destination_container, destination_sponge, is_solid = self:_get_destination_container(output_location)
            if destination_container then
               -- since we're outputting first, we want to process from the end of the line first
               -- that way our destination container will have as much space as it can before we try to output
               if destination_sponge then
                  destination_sponge:on_tick_water_processor()
               end
               output_rate = math.min(output_rate, destination_container:get_available_capacity('stonehearth:water'))
            elseif is_solid then
               output_rate = 0
            end

            if not self._create_water then
               if self._container then
                  -- if we're not creating water, it has to come from our container (which can get fed by input or by others' output)
                  -- update the output_rate based on how much we actually have in the container
                  output_rate = output_rate - self._container:remove_volume('stonehearth:water', output_rate)
               else
                  output_rate = 0
               end
            end

            if output_rate > 0 then
               local volume_not_added = output_rate
               if destination_container then
                  volume_not_added = destination_container:add_volume('stonehearth:water', volume_not_added)
               else
                  -- check if there's a water entity at the output location to add it to
                  -- if not, check where we might want to make a waterfall
                  -- if it makes sense to make a waterfall, do that, otherwise just output water
                  local water_entity
                  if self._prev_output_water_entity and self._prev_output_water_entity:is_valid() then
                     water_entity = self._prev_output_water_entity
                  end
                  
                  if not water_entity then
                     local output_origin = self._sv._output_origin
                     if output_origin then
                        output_origin = radiant.entities.local_to_world(output_origin, self._entity)
                        water_entity = stonehearth.hydrology:get_water_body_at(output_location)
                        if not water_entity then
                           local channel = self._prev_waterfall_channel

                           if not channel then
                              local bottom = stonehearth.hydrology:get_terrain_below(output_location)
                              if output_location ~= bottom then
                                 water_entity = stonehearth.hydrology:get_or_create_water_body_at(bottom)
                                 local channel_manager = stonehearth.hydrology:get_channel_manager()
                                 channel = channel_manager:add_waterfall_channel(output_origin, bottom, self._entity, water_entity)
                                 self._prev_waterfall_channel = channel
                              end
                           end

                           if channel then
                              volume_not_added = channel_manager:add_water_to_waterfall_channel(channel, volume_not_added)
                           end
                        else
                           self._prev_output_water_entity = water_entity
                        end
                     end
                  end

                  if volume_not_added > 0 then
                     local result, info = stonehearth.hydrology:add_water(volume_not_added, output_location, water_entity, true)
                     volume_not_added = result
                     if info then
                        self._prev_output_water_entity = info.water_entity
                        self._prev_waterfall_channel = nil
                     end
                  end
               end

               if volume_not_added > 0 then
                  if self._container then
                     -- if we couldn't add it all, put it back in our container if we have one
                     self._container:add_volume('stonehearth:water', volume_not_added)
                  end

                  self._prev_output_water_entity = nil
                  self._prev_waterfall_channel = nil

                  if volume_not_added == output_rate then
                     self._output_fail_ignores = FAIL_IGNORE_COUNT
                  end
               elseif self._auto_disable_on_full_or_empty and not self._sv.input_enabled and self._container and self._container:is_empty() then
                  self:set_enabled(self._sv.input_enabled, false)
               end
            end
         else
            self._prev_output_water_entity = nil
            self._prev_waterfall_channel = nil
         end
      else
         self._prev_output_water_entity = nil
         self._prev_waterfall_channel = nil
      end
   else
      self._prev_output_water_entity = nil
      self._prev_waterfall_channel = nil
   end

   -- then input water into our container (or destroy water if we don't have one and are set to destroy)

   if self._input_fail_ignores > 0 then
      self._input_fail_ignores = self._input_fail_ignores - 1
   elseif self._sv.input_enabled then
      local input_rate = self:get_input_rate()
      if input_rate > 0 then
         if self._container then
            input_rate = math.min(input_rate, self._container:get_available_capacity('stonehearth:water'))
         elseif not self._destroy_water then
            input_rate = 0
         end

         if input_rate > 0 then
            local input_location = self._sv._input_location
            if input_location then
               input_location = radiant.entities.local_to_world(input_location, self._entity)
               local volume_not_removed = input_rate

               -- the vast majority of the time, we'll be modifying a single water entity
               if self._prev_input_water_entity and self._prev_input_water_entity:is_valid() then
                  volume_not_removed = self:_try_remove_water(self._prev_input_water_entity, input_location, volume_not_removed)
               end

               if volume_not_removed > 0 then
                  local input_region = self._sv._input_region and radiant.entities.local_to_world(self._sv._input_region, self._entity)
                  local water_bodies = self:_get_water_bodies(input_location, input_region)

                  if water_bodies then
                     for _, water_body in ipairs(water_bodies) do
                        -- try removing water from this water body
                        volume_not_removed = self:_try_remove_water(water_body, input_location, volume_not_removed)

                        if volume_not_removed <= 0 then
                           self._prev_input_water_entity = water_body
                           break
                        end
                     end
                  end
               end

               if input_rate > volume_not_removed then
                  if self._container then
                     self._container:add_volume('stonehearth:water', input_rate - volume_not_removed)
                     
                     if self._auto_disable_on_full_or_empty and not self._sv.output_enabled and self._container:is_full() then
                        self:set_enabled(false, self._sv.output_enabled)
                     end
                  end

                  if volume_not_removed > 0 then
                     self._prev_input_water_entity = nil
                  end
               else
                  self._input_fail_ignores = FAIL_IGNORE_COUNT
               end
            end
         else
            self._prev_input_water_entity = nil
         end
      else
         self._prev_input_water_entity = nil
      end
   else
      self._prev_input_water_entity = nil
   end
end

function WaterSpongeComponent:_try_remove_water(water_body, location, volume)
   local water_component = water_body:get_component('stonehearth:water')
   if water_component:get_height() > 0 then
      volume = stonehearth.hydrology:remove_water(volume, location, water_body, true)
   else
      volume = math.max(0, water_component:evaporate(volume / self._wetting_volume) * self._wetting_volume)
   end

   return volume
end

function WaterSpongeComponent:_get_water_bodies(location, region)
	if not location then
		return nil
	end

   if region and region:contains(location) then
      local entities = radiant.terrain.get_entities_in_region(region,
         function(entity)
            return entity:get_component('stonehearth:water') ~= nil
         end)

      if next(entities) then
         local result = {}
         for id, entity in pairs(entities) do
            if entity:get_component('stonehearth:water'):get_region():get():contains(location) then
               table.insert(result, 1, entity)
            else
               table.insert(result, entity)
            end
         end
         return result
      end
   else
      local entities = radiant.terrain.get_entities_at_point(location)
      for id, entity in pairs(entities) do
         local water_component = entity:get_component('stonehearth:water')
         if water_component then
            return { entity }
         end
      end
   end

	return nil
end

function WaterSpongeComponent:_get_destination_container(location)
	if not location then
		return nil, false
	end

	local entities = radiant.terrain.get_entities_at_point(location)

   local container_component = nil
   local sponge_component = nil
	local is_solid = false

	for id, entity in pairs(entities) do
		local container = entity:get_component('stonehearth_ace:container')
		if container and container:get_type() == 'stonehearth:water' then
         container_component = container
         sponge_component = entity:get_component('stonehearth_ace:water_sponge')
         break
      end
      local rcs = entity:get_component('region_collision_shape')
		if rcs and rcs:get_region_collision_type() == _radiant.om.RegionCollisionShape.SOLID then
			is_solid = true
		end
	end

	return container_component, sponge_component, is_solid
end

-- when input/output is enabled/disabled, adjust commands accordingly
-- a pump will have two total commands but only a single command at a time: enable/disable both input and output
-- a sponge will have four total commands but two at a time: toggle mode (absorb/release) and toggle enabled
-- a "buffer" could have four separate commands with two at a time: enable/disable input and enable/disable output
function WaterSpongeComponent:_update_commands()
   local commands = self._json.commands
   if commands then
      local commands_comp = self._entity:add_component('stonehearth:commands')

      self:_ensure_command(not self:is_flow_enabled(), commands_comp, commands.enable_flow)

      self:_ensure_command(not self:is_flow_disabled(), commands_comp, commands.disable_flow)
   end
end

function WaterSpongeComponent:_ensure_command(condition, commands_comp, command)
   if command then
      if condition then
         commands_comp:add_command(command)
      else
         commands_comp:remove_command(command)
      end
   end
end

function WaterSpongeComponent:_update_effects()
   local effects = self._json.effects
   if effects then
      if effects.flow_enabled then
         self:_ensure_effect(self:is_flow_enabled(), 'flow_enabled')
      end

      if effects.flow_disabled then
         self:_ensure_effect(self:is_flow_disabled(), 'flow_disabled')
      end
   end
end

return WaterSpongeComponent
