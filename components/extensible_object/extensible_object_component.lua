local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('extensible_object')

local ExtensibleObjectComponent = class()
local RENDER_MODEL = 'stonehearth_ace:extensible_object|'
local DEFAULT_ROTATION = 'DEFAULT'

function ExtensibleObjectComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._sv._child_entities = {}
   self._sv.cur_extensions = {}
end

function ExtensibleObjectComponent:create()
	self._is_create = true
end

function ExtensibleObjectComponent:restore()
end

function ExtensibleObjectComponent:activate()
	self._extend_command = self._json.extend_command or 'stonehearth_ace:commands:extensible_object:extend'
	self._remove_command = self._json.remove_command or 'stonehearth_ace:commands:extensible_object:remove'
	self._extension_entity = self._json.extension_entity or 'stonehearth_ace:extensible_object:extension'
	self._render_model = self._json.render_model
   self._rotations = radiant.util.get_rotations_table(self._json)
end

function ExtensibleObjectComponent:post_activate()
   if self._is_create then
      self:_ensure_base_connections()
   end
	self:_ensure_child_entities()
   self:_update_commands()
end

function ExtensibleObjectComponent:destroy()
	self:_destroy_child_entities()
end

function ExtensibleObjectComponent:_destroy_child_entities()
   for _, entity in pairs(self._sv._child_entities) do
      radiant.entities.destroy_entity(entity)
   end
   self._sv._child_entities = {}
end

function ExtensibleObjectComponent:_ensure_child_entities()
   for _, rotation in ipairs(self._rotations) do
      local id = self:_get_rotation_id(rotation)
      
      if not self._sv._child_entities[id] then
         local entity = radiant.entities.create_entity(self._extension_entity, { owner = self._entity })
         entity:add_component('region_collision_shape'):set_region(_radiant.sim.alloc_region3())
         radiant.entities.add_child(self._entity, entity, Point3.zero, true)
         self._sv._child_entities[id] = entity
      end
   end
end

function ExtensibleObjectComponent:_ensure_base_connections()
   -- go through the rotations and make sure connections get set to their base untranslated regions
   -- first check to see if any rotations actually have connections specified
   local has_connections = false
   for _, rotation in ipairs(self._rotations) do
      if rotation.connection_type and rotation.connector_id and rotation.connector_region then
         has_connections = true
         break
      end
   end

   if not has_connections then
      return
   end

   local dc = self._entity:add_component('stonehearth_ace:dynamic_connection')
   for _, rotation in ipairs(self._rotations) do
      if rotation.connection_type and rotation.connector_id and rotation.connector_region then
         dc:update_region(rotation.connection_type, rotation.connector_id, rotation.connector_region)
      end
   end
end

function ExtensibleObjectComponent:get_rotations()
   return self._rotations
end

function ExtensibleObjectComponent:set_extension(rotation_index, length, collision_region, connector_region, output_point, output_origin)
   log:debug('%s extensible_object:set_extension(%s, %s, %s, %s, %s, %s)',
         self._entity, tostring(rotation_index), tostring(length),
         collision_region and collision_region:get_bounds() or 'nil',
         connector_region and connector_region:get_bounds() or 'nil',
         tostring(output_point), tostring(output_origin))

   local data
   local rotation = self._rotations[rotation_index]
   if not rotation then
      self:_clear_all_extensions()
      self:_update_commands()
      return
   end

   local rotation_id = self:_get_rotation_id(rotation)
   local model_name = self:_get_model_name(rotation_id)
   local child = self._sv._child_entities[rotation_id]
   local rcs = child:add_component('region_collision_shape')
   local region = rcs:get_region()
   local models_comp = self._entity:add_component('stonehearth_ace:models')

   if length > 0 then
      region:modify(function(cursor)
         cursor:copy_region(collision_region)
      end)

      local data = radiant.shallow_copy(rotation)
      data.length = length
      models_comp:set_model_options(model_name, data)
      self._sv.cur_extensions[rotation_id] = true
   else
      stonehearth.hydrology:auto_fill_water_region(radiant.entities.local_to_world(region:get(), self._entity), function(waters)
            region:modify(function(cursor)
               cursor:clear()
            end)

            return true
         end)
         
      models_comp:remove_model(model_name)
      self._sv.cur_extensions[rotation_id] = nil
   end

   self:_update_commands()
   self.__saved_variables:mark_changed()

   local dc = self._entity:get_component('stonehearth_ace:dynamic_connection')
   if dc and rotation.connection_type then
      dc:update_region(rotation.connection_type, rotation_id, connector_region)
   end

   radiant.events.trigger(self._entity, 'stonehearth_ace:extensible_object:extension_changed', {
      length = length,
      output_point = output_point,
      output_origin = output_origin,
   })
end

function ExtensibleObjectComponent:_get_rotation_id(rotation)
   return rotation and rotation.connector_id or DEFAULT_ROTATION
end

function ExtensibleObjectComponent:_get_model_name(rotation_id)
   return RENDER_MODEL .. rotation_id
end

function ExtensibleObjectComponent:_clear_all_extensions()
   local models_comp = self._entity:add_component('stonehearth_ace:models')
   local dc = self._entity:get_component('stonehearth_ace:dynamic_connection')

   for index, rotation in ipairs(self._rotations) do
      local id = self:_get_rotation_id(rotation)
      local child = self._sv._child_entities[id]

      if child then
         -- add water to the original region if it was displacing any
         local region = child:add_component('region_collision_shape'):get_region()
         stonehearth.hydrology:auto_fill_water_region(radiant.entities.local_to_world(region:get(), self._entity), function(waters)
            region:modify(function(cursor)
               cursor:clear()
            end)

            return true
         end)
      end

      models_comp:remove_model(self:_get_model_name(id))

      if dc and rotation.connection_type then
         dc:update_region(rotation.connection_type, id, rotation.connector_region)
      end
   end

   self._sv.cur_extensions = {}
   self.__saved_variables:mark_changed()
end

function ExtensibleObjectComponent:_update_commands()
   local commands = self._entity:add_component('stonehearth:commands')
   if next(self._sv.cur_extensions) then
      if #self._rotations == 1 then
         commands:remove_command(self._extend_command)
      end
      commands:add_command(self._remove_command)

      -- also disable the move/undeploy commands, if they exist, since it doesn't play well with the extended pipe
      commands:set_command_enabled('stonehearth:commands:move_item', false)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', false)

      -- also cancel any move/undeploy tasks for it currently underway
      local entity_forms_component = self._entity:get_component('stonehearth:entity_forms')
      if entity_forms_component then
         entity_forms_component:cancel_placement_tasks()
      end
   else
      commands:remove_command(self._remove_command)
      commands:add_command(self._extend_command)

      commands:set_command_enabled('stonehearth:commands:move_item', true)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', true)
   end
end

return ExtensibleObjectComponent
