local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local rng = _radiant.math.get_default_rng()
local log = radiant.log.create_logger('extensible_object')

local ExtensibleObjectComponent = class()
local RENDER_MODEL = 'stonehearth_ace:extensible_object|'
local DEFAULT_ROTATION = 'DEFAULT'

function ExtensibleObjectComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._sv._child_entities = {}
   self._sv._end_entities = {}
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

   self._parent_trace = self._entity:add_component('mob')
      :trace_parent('extensible object parent change', _radiant.dm.TraceCategories.SYNC_TRACE)
         :on_changed(function(parent)
               if not parent then
                  self:set_extension(nil)
               end
            end)
end

function ExtensibleObjectComponent:destroy()
	self:_destroy_child_entities()
   self:_destroy_end_entities()

   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
end

function ExtensibleObjectComponent:_destroy_child_entities()
   for _, entity in pairs(self._sv._child_entities) do
      radiant.entities.destroy_entity(entity)
   end
   self._sv._child_entities = {}
end

function ExtensibleObjectComponent:_destroy_end_entities()
   for _, entity in pairs(self._sv._end_entities) do
      radiant.entities.destroy_entity(entity)
   end
   self._sv._end_entities = {}
end

function ExtensibleObjectComponent:_destroy_end_entity(rotation_id)
   local entity = self._sv._end_entities[rotation_id]
   if entity then
      radiant.entities.destroy_entity(entity)
      self._sv._end_entities[rotation_id] = nil
   end
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

-- TODO: allow for a rotation to specify which direction the end entity should face
function ExtensibleObjectComponent:_ensure_end_entity(rotation_id, uri, location)
   local world_location = radiant.entities.local_to_world(Region3(Cube3(location)), self._entity):get_bounds().min
   local parent = radiant.entities.get_parent(self._entity)
   local facing = radiant.entities.get_facing(self._entity)
   local rel_location = radiant.entities.world_to_local(world_location, parent)
   local entity = self._sv._end_entities[rotation_id]
   if not entity then
      entity = radiant.entities.create_entity(uri, { owner = self._entity })
      entity:add_component('mob'):set_ignore_gravity(true)
      radiant.entities.turn_to(entity, facing)
      radiant.entities.add_child(parent, entity, rel_location)
      --radiant.entities.add_child(self._entity, entity, location, true)
      self._sv._end_entities[rotation_id] = entity

      -- inform the entity about its parent to any component that wants to listen
      radiant.events.trigger(entity, 'stonehearth_ace:extensible_object:end_entity_created', { parent = self._entity })
   else
      radiant.entities.turn_to(entity, facing)
      radiant.entities.move_to(entity, rel_location)
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

   local rotation = self._rotations[rotation_index]
   if not rotation then
      radiant.events.trigger(self._entity, 'stonehearth_ace:extensible_object:extension_cleared')
      self:_clear_all_extensions()
      self:_update_commands()
      self:_destroy_end_entities()
      self._sv._cur_rotation_index = nil
      return
   end

   local rotation_id = self:_get_rotation_id(rotation)
   local model_name = self:_get_model_name(rotation_id)
   local child = self._sv._child_entities[rotation_id]
   local rcs = child:add_component('region_collision_shape')
   local vpr = child:get_component('stonehearth_ace:vertical_pathing_region')
   local region = rcs:get_region()
   local models_comp = self._entity:add_component('stonehearth_ace:models')

   if length then
      if rotation_id == DEFAULT_ROTATION then
         self._sv._cur_rotation_index = rotation_index
      end

      self:_modify_collision_region(region, collision_region)

      if vpr then
         vpr:set_region(collision_region)
      end

      local data = radiant.shallow_copy(rotation)
      data.length = length

      if data.multi_matrix_mode == 'random' and radiant.util.is_table(data.matrix) then
         data.matrix = {data.matrix[rng:get_int(1, #data.matrix)]}
      end

      models_comp:set_model_options(model_name, data)
      self._sv.cur_extensions[rotation_id] = true

      if rotation.end_entity then
         self:_ensure_end_entity(rotation_id, rotation.end_entity, output_point)
      end
   else
      radiant.events.trigger(self._entity, 'stonehearth_ace:extensible_object:extension_cleared', { rotation_index = rotation_index })
      self:_modify_collision_region(region, nil)

      if vpr then
         vpr:set_region()
      end

      models_comp:remove_model(model_name)
      self._sv.cur_extensions[rotation_id] = nil

      self:_destroy_end_entity(rotation_id)

      if rotation_id == DEFAULT_ROTATION then
         self._sv._cur_rotation_index = nil
      end
   end

   if self._json.extended_model_variant then
      local render_info = self._entity:add_component('render_info')
      render_info:set_model_variant('extended')
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

function ExtensibleObjectComponent:_modify_collision_region(region, new_region)
   local diff_region = region:get()
   if new_region then
      diff_region = diff_region - new_region
   end

   log:debug('modifying collision region: %s to %s', diff_region:get_bounds(), tostring(new_region and new_region:get_bounds()))
   stonehearth.hydrology:auto_fill_water_region(radiant.entities.local_to_world(diff_region, self._entity), function(waters)
         log:debug('auto-filling water region...')
         region:modify(function(cursor)
            if new_region then
               cursor:copy_region(new_region)
            else
               cursor:clear()
            end
         end)

         return true
      end)
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
      log:debug('clearing extension id %s: %s', index, id)
      if id ~= DEFAULT_ROTATION or not self._sv._cur_rotation_index or index == self._sv._cur_rotation_index then
         local child = self._sv._child_entities[id]

         if child then
            -- add water to the original region if it was displacing any
            local region = child:add_component('region_collision_shape'):get_region()
            self:_modify_collision_region(region, nil)

            local vpr = child:get_component('stonehearth_ace:vertical_pathing_region')
            if vpr then
               vpr:set_region()
            end
         end

         models_comp:remove_model(self:_get_model_name(id))

         if dc and rotation.connection_type then
            dc:update_region(rotation.connection_type, id, rotation.connector_region)
         end
      end
   end

   if self._json.extended_model_variant then
      local render_info = self._entity:add_component('render_info')
      render_info:set_model_variant('default')
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
