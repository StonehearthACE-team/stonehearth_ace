--[[
   the core water functionality has been shifted to the water_sponge component
   now this component primarily handles the extendable pipe aspect
]]

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('water_pump')

local WaterPumpComponent = class()

local RENDER_MODEL = 'stonehearth_ace:water_pump'

function WaterPumpComponent:initialize()
   self._json = radiant.entities.get_json(self)
end

function WaterPumpComponent:create()
	self._is_create = true
end

function WaterPumpComponent:restore()
	if self._sv.rate then
      -- old version of pump; needs to have its topper destroyed
      self._sv.rate = nil
      self._sv.depth = nil
      self._sv.height = nil
      self._sv.topper_region = nil
      if self._sv._pump_child_entity then
         radiant.entities.destroy_entity(self._sv._pump_child_entity)
         self._sv._pump_child_entity = nil
      end

      self.__saved_variables:mark_changed()
      self._is_create = true
   end

   if self._sv.pipe_render_data then
      self._sv.pipe_render_data = nil
      self.__saved_variables:mark_changed()
   end
end

function WaterPumpComponent:activate()
   self._rotations = radiant.util.get_rotations_table(self._json)
end

function WaterPumpComponent:post_activate()
   self:_ensure_child_entity()
   self:_update_commands()
end

function WaterPumpComponent:destroy()
   --When the water tool is destroyed, destroy any other child entities
   self:_destroy_child_entity()
end

function WaterPumpComponent:_ensure_child_entity()
   if not self._sv._pump_child_entity then
      self._sv._pump_child_entity = radiant.entities.create_entity('stonehearth_ace:gizmos:water_pump_pipe', { owner = self._entity })
      self._sv._pump_child_entity:add_component('region_collision_shape'):set_region(_radiant.sim.alloc_region3())
      radiant.entities.add_child(self._entity, self._sv._pump_child_entity, Point3.zero, true)
   end
end

function WaterPumpComponent:_destroy_child_entity()
   if self._sv._pump_child_entity then
		radiant.entities.destroy_entity(self._sv._pump_child_entity)
		self._sv._pump_child_entity = nil
	end
end

function WaterPumpComponent:get_rotations()
   return self._rotations
end

-- whatever calls this should also call the water_sponge component's set_output_location
-- refactored to outsource pipe rendering to the models component instead of using a custom renderer
function WaterPumpComponent:set_pipe_extension(rotation_index, length, collision_region)
   local data
   local rotation = self._rotations[rotation_index]

   local rcs = self._sv._pump_child_entity:add_component('region_collision_shape')
   local region = rcs:get_region()
   local models_comp = self._entity:add_component('stonehearth_ace:models')

   if rotation and length > 0 then
      self._sv.extended = true
      region:modify(function(cursor)
         -- copy_region also clears the existing region
         cursor:copy_region(collision_region)
      end)

      local data = radiant.shallow_copy(rotation)
      data.length = length
      models_comp:set_model_options(RENDER_MODEL, data)
   else
      self._sv.extended = false
      region:modify(function(cursor)
         cursor:clear()
      end)

      models_comp:remove_model(RENDER_MODEL)
   end

   self:_update_commands()
   self.__saved_variables:mark_changed()
end

function WaterPumpComponent:_update_commands()
   -- if the pipe is currently extended, give it the remove command; otherwise give it the place command
   local commands = self._entity:add_component('stonehearth:commands')
   if self._sv.extended then
      commands:remove_command('stonehearth_ace:commands:water_pipe:place')
      commands:add_command('stonehearth_ace:commands:water_pipe:remove')

      -- also disable the move/undeploy commands, if they exist, since it doesn't play well with the extended pipe
      commands:set_command_enabled('stonehearth:commands:move_item', false)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', false)

      -- also cancel any move/undeploy tasks for it currently underway
      local entity_forms_component = self._entity:get_component('stonehearth:entity_forms')
      if entity_forms_component then
         entity_forms_component:cancel_placement_tasks()
      end
   else
      commands:remove_command('stonehearth_ace:commands:water_pipe:remove')
      commands:add_command('stonehearth_ace:commands:water_pipe:place')

      commands:set_command_enabled('stonehearth:commands:move_item', true)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', true)
   end
end

return WaterPumpComponent
