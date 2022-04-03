--[[
   like the water pump (pipe) component, the gearbox (axle) component allows axles to be extended from the gearbox entity
   
]]

local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local log = radiant.log.create_logger('gearbox')

local GearboxComponent = class()
local RENDER_MODEL = 'stonehearth_ace:gearbox|'

function GearboxComponent:initialize()
   self._json = radiant.entities.get_json(self)
   self._sv._axle_child_entities = {}
   self._sv.cur_axles = {}
end

function GearboxComponent:create()
	self._is_create = true
end

function GearboxComponent:activate()
   self._rotations = radiant.util.get_rotations_table(self._json)
end

function GearboxComponent:post_activate()
   if self._is_create then
      self:_ensure_base_connections()
   end
   self:_ensure_child_entities()
   self:_update_commands()
end

function GearboxComponent:destroy()
   --When the gearbox is destroyed, destroy any other child entities
   self:_destroy_child_entities()
   self:_clear_all_axles()
end

function GearboxComponent:_ensure_base_connections()
   -- go through the rotations and make sure connections get set to their base untranslated regions
   local dc = self._entity:add_component('stonehearth_ace:dynamic_connection')
   for _, rotation in ipairs(self._rotations) do
      dc:update_region(rotation.connection_type, rotation.connector_id, rotation.connector_region)
   end
end

-- would it be better to have a single child entity with a wacky collision region?
-- that would require keeping track of the collision regions separately still for when one is changed/removed
function GearboxComponent:_ensure_child_entities()
   -- index them by their connector id
   for _, rotation in ipairs(self._rotations) do
      local id = rotation.connector_id
      
      if not self._sv._axle_child_entities[id] then
         local entity = radiant.entities.create_entity('stonehearth_ace:gizmos:axles:gear_box_axle', { owner = self._entity })
         entity:add_component('region_collision_shape'):set_region(_radiant.sim.alloc_region3())
         radiant.entities.add_child(self._entity, entity, Point3.zero, true)
         self._sv._axle_child_entities[id] = entity
      end
   end
end

function GearboxComponent:_destroy_child_entities()
   for _, entity in pairs(self._sv._axle_child_entities) do
      radiant.entities.destroy_entity(entity)
   end
   self._sv._axle_child_entities = {}
end

function GearboxComponent:get_rotations()
   return self._rotations
end

function GearboxComponent:set_axle_extension(rotation_index, length, connector_region, collision_region)
   -- if no valid rotation_index specified, clear all axles
   local rotation = self._rotations[rotation_index]
   if not rotation_index or not rotation then
      self:_clear_all_axles()
      self:_update_commands()
      return
   end

   local id = rotation.connector_id
   local child = self._sv._axle_child_entities[id]
   local rcs = child:add_component('region_collision_shape')
   local region = rcs:get_region()
   local models_comp = self._entity:add_component('stonehearth_ace:models')

   if length > 0 then
      region:modify(function(cursor)
         cursor:copy_region(collision_region)
      end)

      local data = radiant.shallow_copy(rotation)
      data.length = length
      models_comp:set_model_options(self:_get_model_name(id), data)
      self._sv.cur_axles[id] = true
   else
      -- add water to the original region if it was displacing any
      stonehearth.hydrology:auto_fill_water_region(radiant.entities.local_to_world(region:get(), self._entity), function(waters)
         region:modify(function(cursor)
            cursor:clear()
         end)

         return true
      end)

      models_comp:remove_model(self:_get_model_name(id))
      self._sv.cur_axles[id] = nil
   end

   self.__saved_variables:mark_changed()

   local dc = self._entity:add_component('stonehearth_ace:dynamic_connection')
   dc:update_region(rotation.connection_type, id, connector_region)

   self:_update_commands()
end

function GearboxComponent:_get_model_name(id)
   return RENDER_MODEL .. id
end

function GearboxComponent:_clear_all_axles()
   local models_comp = self._entity:add_component('stonehearth_ace:models')
   local dyn_conn_comp = self._entity:add_component('stonehearth_ace:dynamic_connection')

   for index, rotation in ipairs(self._rotations) do
      local id = rotation.connector_id
      local child = self._sv._axle_child_entities[id]

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
      dyn_conn_comp:update_region(rotation.connection_type, id, rotation.connector_region)
   end

   self._sv.cur_axles = {}
   self.__saved_variables:mark_changed()
end

function GearboxComponent:_update_commands()
   local commands = self._entity:add_component('stonehearth:commands')
   commands:add_command('stonehearth_ace:commands:mechanical:adjust_gearbox_axles')

   if next(self._sv.cur_axles) then
      commands:add_command('stonehearth_ace:commands:mechanical:reset_gearbox_axles')

      -- disable the move/undeploy commands, if they exist, since it doesn't play well with the extended axles
      commands:set_command_enabled('stonehearth:commands:move_item', false)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', false)

      -- also cancel any move/undeploy tasks for it currently underway
      local entity_forms_component = self._entity:get_component('stonehearth:entity_forms')
      if entity_forms_component then
         entity_forms_component:cancel_placement_tasks()
      end
   else
      commands:remove_command('stonehearth_ace:commands:mechanical:reset_gearbox_axles')

      commands:set_command_enabled('stonehearth:commands:move_item', true)
      commands:set_command_enabled('stonehearth:commands:undeploy_item', true)
   end
end

return GearboxComponent
