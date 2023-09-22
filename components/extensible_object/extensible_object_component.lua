local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('extensible_object')

local ExtensibleObjectComponent = class()

function ExtensibleObjectComponent:initialize()
   self._json = radiant.entities.get_json(self)
end

function ExtensibleObjectComponent:create()
	self._is_create = true
end

function ExtensibleObjectComponent:restore()
end

function ExtensibleObjectComponent:activate()
	self._sv.extend_command = self._json.extend_command or 'stonehearth_ace:commands:extensible_object:extend'
	self._sv.remove_command = self._json.remove_command or 'stonehearth_ace:commands:extensible_object:remove'
	self._sv.extension_entity = self._json.extension_entity
	self._sv.render_model = self._json.render_model
	self.__saved_variables:mark_changed()
   self._rotations = radiant.util.get_rotations_table(self._json)
end

function ExtensibleObjectComponent:post_activate()
	self:_ensure_child_entity()
   self:_update_commands()
end

function ExtensibleObjectComponent:destroy()
	self:_destroy_child_entity()
end

function ExtensibleObjectComponent:_destroy_child_entity()
   if self._sv._child_entity then
		radiant.entities.destroy_entity(self._sv._child_entity)
		self._sv._child_entity = nil
	end
end

function ExtensibleObjectComponent:_ensure_child_entity()
   if not self._sv._child_entity then
      self._sv._child_entity = radiant.entities.create_entity(self._sv.extension_entity, { owner = self._entity })
      self._sv._child_entity:add_component('region_collision_shape'):set_region(_radiant.sim.alloc_region3())
      radiant.entities.add_child(self._entity, self._sv._child_entity, Point3.zero, true)
   end
end

function ExtensibleObjectComponent:get_rotations()
   return self._rotations
end

function ExtensibleObjectComponent:set_extension(rotation_index, length, collision_region)
   local data
   local rotation = self._rotations[rotation_index]

   local child = self._sv._child_entity
   local rcs = child:add_component('region_collision_shape')
   local region = rcs:get_region()
   local models_comp = self._entity:add_component('stonehearth_ace:models')

   if rotation and length > 0 then
      self._sv.extended = true
      region:modify(function(cursor)
         cursor:copy_region(collision_region)
      end)

      local data = radiant.shallow_copy(rotation)
      data.length = length
      models_comp:set_model_options(self._sv.render_model, data)
   else
      self._sv.extended = false

      stonehearth.hydrology:auto_fill_water_region(radiant.entities.local_to_world(region:get(), self._entity), function(waters)
            region:modify(function(cursor)
               cursor:clear()
            end)

            return true
         end)
         
      models_comp:remove_model(self._sv.render_model)
   end

   self:_update_commands()
   self.__saved_variables:mark_changed()
end

function ExtensibleObjectComponent:_update_commands()
   local commands = self._entity:add_component('stonehearth:commands')
   if self._sv.extended then
      commands:remove_command(self._sv.extend_command)
      commands:add_command(self._sv.remove_command)

      -- also disable the move/undeploy commands, if they exist, since it doesn't play well with the extended pipe
      commands:set_command_enabled('stonehearth:commands:move_item', false)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', false)

      -- also cancel any move/undeploy tasks for it currently underway
      local entity_forms_component = self._entity:get_component('stonehearth:entity_forms')
      if entity_forms_component then
         entity_forms_component:cancel_placement_tasks()
      end
   else
      commands:remove_command(self._sv.remove_command)
      commands:add_command(self._sv.extend_command)

      commands:set_command_enabled('stonehearth:commands:move_item', true)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', true)
   end
end

return ExtensibleObjectComponent
