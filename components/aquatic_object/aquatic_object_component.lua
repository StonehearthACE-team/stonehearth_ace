local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Cube3 = _radiant.csg.Cube3
local rng = _radiant.math.get_default_rng()

local log = radiant.log.create_logger('aquatic_object')

local AquaticObjectComponent = class()

function AquaticObjectComponent:initialize()
   self._sv.in_the_water = nil
   
   self._sv.original_origin = self._entity:get_component('mob'):get_model_origin() or Point3.zero
   
   self._json = radiant.entities.get_json(self)
   if self._json then
      self._require_water_to_grow = self._json.require_water_to_grow
      self._destroy_if_out_of_water = self._json.destroy_if_out_of_water
      self._suffocate_if_out_of_water = self._json.suffocate_if_out_of_water
      self._floating_object = self._json.floating_object
      self._swimming_object = self._json.swimming_object
   end
end

function AquaticObjectComponent:create()
   self._sv._floating_enabled = self._floating_object and self._floating_object.floating_enabled ~= false
end

function AquaticObjectComponent:post_activate()
   if not self._json then
      self._entity:remove_component('stonehearth_ace:aquatic_object')
      return
   end

   self:_create_listeners()
   
   -- only call these if we're already placed in the world
   local location = radiant.entities.get_world_location(self._entity)
   if location then
      self:_on_water_exists_changed()
      self:_on_water_surface_level_changed()
   end
end

function AquaticObjectComponent:_create_listeners()
   local signal_region = self._json.water_signal_region
   if signal_region then
      local region = Region3()
      region:load(signal_region)
      signal_region = region
   else
      -- make sure it's extruded downwards by 1
      signal_region = {y = {1, 0}}
   end

   local monitor_types = {}
   if self._require_water_to_grow or self._destroy_if_out_of_water or self._suffocate_if_out_of_water or self._swimming_object then
      table.insert(monitor_types, 'water_exists')
   end
   if self._suffocate_if_out_of_water or self._floating_object or self._swimming_object then
      table.insert(monitor_types, 'water_surface_level')
   end
   
   local water_signal = self._entity:add_component('stonehearth_ace:water_signal')
   self._water_signal = water_signal:set_signal('aquatic_object', signal_region, monitor_types, function(changes) self:_on_water_signal_changed(changes) end)
end

function AquaticObjectComponent:_on_water_signal_changed(changes)
   if changes.water_exists then
      self:_on_water_exists_changed(changes.water_exists.value)
   end

   if changes.water_surface_level then
      self:_on_water_surface_level_changed(changes.water_surface_level.value)
   end
end

function AquaticObjectComponent:_on_water_exists_changed(exists)
   if exists == nil then
      exists = self._water_signal:get_water_exists()
   end

   self._sv.in_the_water = exists
   self.__saved_variables:mark_changed()

   if self._require_water_to_grow then
      self:timers_resume(exists)
   end
   
   -- if water goes away completely, water_surface_level may not get reported, but it should definitely suffocate
   if not exists then
      self:suffocate_entity()
      self:stop_swim()
   end
   
   if self._destroy_if_out_of_water and not self._sv.in_the_water and not self._queued_destruction then
      self:queue_destruction()
   end
end

function AquaticObjectComponent:_on_water_surface_level_changed(level)
   if level == nil then
      level = self._water_signal:get_water_surface_level()
   end

   self:float(level)
   self:swim(level)
   -- if a surface level is getting reported, water exists, so this handles the case of water suddenly appearing
   self:suffocate_entity(level)
end

function AquaticObjectComponent:suffocate_entity(level)
   if not self._suffocate_if_out_of_water then 
      return
   end
   
   local entity_height = self._suffocate_if_out_of_water.entity_height or 1
   local entity_location = radiant.entities.get_world_location(self._entity)
   local entity_breathing_line = nil
   
   if entity_location then
      entity_breathing_line = entity_location.y + entity_height
      if level == nil then
         radiant.entities.add_buff(self._entity, 'stonehearth_ace:buffs:suffocating')
      elseif level < entity_breathing_line then
         radiant.entities.add_buff(self._entity, 'stonehearth_ace:buffs:suffocating')
      else 
         radiant.entities.remove_buff(self._entity, 'stonehearth_ace:buffs:suffocating')
      end
   end
end

function AquaticObjectComponent:queue_destruction()
   self._queued_destruction = function()
      if not self._sv.in_the_water then
         radiant.entities.kill_entity(self._entity)         
      end
   end

   stonehearth_ace.water_signal:add_next_tick_callback(self._queued_destruction, self)
end

function AquaticObjectComponent:set_float_enabled(enabled)
   self._sv._floating_enabled = enabled
   if enabled then
      self:float(self._water_signal and self._water_signal:get_water_surface_level())
   end
end

function AquaticObjectComponent:float(level)
   if not self._floating_object or not self._sv._floating_enabled then
      return
   end
   
   local vertical_offset = self._floating_object.vertical_offset or 0
   local location = radiant.entities.get_world_location(self._entity)
   if location then
      local lowest = radiant.terrain.get_standable_point(location).y

      if level then
         location.y = math.max(lowest, level + vertical_offset)
         self._entity:add_component('mob'):set_ignore_gravity(true)
      else
         location.y = lowest
      end
      
      radiant.entities.move_to(self._entity, location)
   end
end

function AquaticObjectComponent:swim(level)
   if not self._swimming_object then
      return
   end
   
   local vertical_offset = self._swimming_object.vertical_offset or 0
   local location = radiant.entities.get_world_location(self._entity)
   local mob_component = self._entity:get_component('mob')
   local model_origin = mob_component:get_model_origin()
   
   if location and model_origin and level then
      local lowest = radiant.terrain.get_standable_point(location).y
      local depth = (level - lowest) + vertical_offset
      
      if depth >= (self._swimming_object.minimum_depth or 0) then
         if self._swimming_object.surface then
            model_origin.y = math.max(model_origin.y, depth) * -1
         elseif self._swimming_object.bottom then
            model_origin.y = math.max(model_origin.y, (depth / rng:get_real(4, 5))) * -1
         else
            model_origin.y = math.max(model_origin.y, (depth / rng:get_real(2, 5))) * -1
         end 
      end
      
      mob_component:set_model_origin(model_origin)
   end
end

function AquaticObjectComponent:stop_swim()
   if not self._swimming_object then
      return
   end

   self._entity:get_component('mob'):set_model_origin(self._sv.original_origin)
end

function AquaticObjectComponent:timers_resume(resume)
   local renewable_resource_node_component = self._entity:get_component('stonehearth:renewable_resource_node')
   local evolve_component = self._entity:get_component('stonehearth:evolve')
   --local growing_component = self._entity:get_component('stonehearth:growing')
   
   if renewable_resource_node_component then
      if resume then
         renewable_resource_node_component:resume_resource_timer()
      else
         renewable_resource_node_component:pause_resource_timer()
      end
   end
   
   if evolve_component then
      if resume then
         evolve_component:_start_evolve_timer()
      else
         evolve_component:_stop_evolve_timer()
      end
   end
   
   -- if growing_component then
   --    if resume then
   --       growing_component:start_growing()
   --    else
   --       growing_component:stop_growing()
   --    end
   -- end
end

function AquaticObjectComponent:destroy()
   self:_destroy_listeners()
end

function AquaticObjectComponent:_destroy_listeners()
   if self._water_listener then
      self._water_listener:destroy()
      self._water_listener = nil
   end
end

return AquaticObjectComponent
