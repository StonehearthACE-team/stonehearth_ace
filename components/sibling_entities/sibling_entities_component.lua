local TraceCategories = _radiant.dm.TraceCategories
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local entity_forms_lib = require 'stonehearth.lib.entity_forms.entity_forms_lib'

local SiblingEntitiesComponent = class()

local log = radiant.log.create_logger('sibling_entities')

function SiblingEntitiesComponent:initialize()
   self._sv.siblings = {}

   self._json = radiant.entities.get_json(self) or {}
   self._region_traces = {}
   self._sibling_predestroy_traces = {}
end

function SiblingEntitiesComponent:create()
   self._is_create = true
end

function SiblingEntitiesComponent:activate()
   self._player_id_trace = self._entity:trace_player_id('sibling entities component player id changed', TraceCategories.SYNC_TRACE)
      :on_changed(function()
            self:_update_player_id()
         end)

   self._parent_trace = self._entity:add_component('mob'):trace_parent('sibling entities component primary entity added or removed')
      :on_changed(function(parent_entity)
            if not parent_entity then
               --we were just removed from the world; remove all siblings
               self:_remove_all_siblings_from_parent()
            else
               --we were just added to the world; add all siblings
               self:_add_all_siblings_to_parent()
            end
         end)

   -- does this trigger on facing/rotation changes? or just location/translation changes?
   self._location_trace = radiant.entities.trace_location(self._entity, 'sibling entities component primary entity location changed')
      :on_changed(function()
            self:_update_siblings()
         end)

   if self._is_create and self._json.siblings then
      for id, sibling_spec in pairs(self._json.siblings) do
         sibling_spec.key = id
         self:add_sibling(sibling_spec)
      end
   end

   self:_create_sibling_predestroy_traces()
   self:_create_region_traces()
end

function SiblingEntitiesComponent:destroy()
   if self._parent_trace then
      self._parent_trace:destroy()
      self._parent_trace = nil
   end
   if self._player_id_trace then
      self._player_id_trace:destroy()
      self._player_id_trace = nil
   end
   if self._location_trace then
      self._location_trace:destroy()
      self._location_trace = nil
   end
   self:_destroy_region_traces()

   for id, sibling in pairs(self._sv.siblings) do
      self:_destroy_sibling(id)
   end
   self._sv.siblings = {}
end

function SiblingEntitiesComponent:_destroy_sibling(id)
   self:_destroy_predestroy_trace(id)

   local sibling = self._sv.siblings[id]
   if sibling then
      self._sv.siblings[id] = nil
      -- if the sibling spec says the entity shouldn't be destroyed, simply enable gravity
      -- if it says it should be iconified, do that
      -- otherwise, destroy it
      if sibling.destroy_on_remove then
         radiant.entities.destroy_entity(sibling.entity)
      else
         if sibling.ignore_gravity ~= false then
            sibling.entity:add_component('mob'):set_ignore_gravity(false)
         end

         if sibling.iconify_on_remove ~= false then
            local root_form, iconic_form = entity_forms_lib.get_forms(sibling.entity)
            if iconic_form then
               local location = radiant.entities.get_world_location(root_form)
               radiant.terrain.remove_entity(root_form)
               radiant.terrain.place_entity_at_exact_location(iconic_form, location)
            end
         end
      end
   end
end

function SiblingEntitiesComponent:_destroy_predestroy_trace(id)
   if self._sibling_predestroy_traces[id] then
      self._sibling_predestroy_traces[id]:destroy()
      self._sibling_predestroy_traces[id] = nil
   end
end

function SiblingEntitiesComponent:_create_sibling_predestroy_traces()
   for id, sibling in pairs(self._sv.siblings) do
      self:_create_sibling_predestroy_trace(sibling.entity)
   end
end

function SiblingEntitiesComponent:_create_sibling_predestroy_trace(entity)
   local id = entity:get_id()
   self._sibling_predestroy_traces[id] = radiant.events.listen(entity, 'radiant:entity:pre_destroy', function()
         self:_destroy_predestroy_trace(id)
         self._sv.siblings[id] = nil
         self.__saved_variables:mark_changed()
      end)
end

function SiblingEntitiesComponent:_create_region_traces()
   local comp_traces = {}
   for id, sibling in pairs(self._sv.siblings) do
      if sibling.match_component_regions then
         for component_name, match in pairs(sibling.match_component_regions) do
            comp_traces[component_name] = match or comp_traces[component_name] or nil
         end
      end
   end

   for component_name, _ in pairs(comp_traces) do
      if not self._region_traces[component_name] then
         local component = self._entity:get_component(component_name)
         if component and component.get_region and component.set_region then
            self._region_traces[component_name] = component:get_region():trace('sibling entities component')
               :on_changed(function()
                     self:_update_siblings(component_name)
                  end)
               :push_object_state()
         end
      end
   end
end

function SiblingEntitiesComponent:_destroy_region_traces()
   for id, trace in pairs(self._region_traces) do
      trace:destroy()
   end
   self._region_traces = {}
end

function SiblingEntitiesComponent:get_sibling(key)
   for id, sibling in pairs(self._sv.siblings) do
      if sibling.key == key then
         return sibling.entity
      end
   end
end

function SiblingEntitiesComponent:add_sibling(sibling_spec)
   local mob = self._entity:get_component('mob')
   local parent = mob and mob:get_parent()

   local entity = radiant.entities.create_entity(sibling_spec.uri, { owner = self._entity })
   local entity_mob = entity:add_component('mob')
   entity_mob:set_region_origin(mob:get_region_origin())
   entity_mob:set_align_to_grid_flags(mob:get_align_to_grid_flags())
   if sibling_spec.ignore_gravity ~= false then
      entity_mob:set_ignore_gravity(true)
   end

   local sibling = {
      entity = entity,
      key = sibling_spec.key,
      ignore_gravity = sibling_spec.ignore_gravity,
      match_component_regions = sibling_spec.match_component_regions or {},
      offset = sibling_spec.offset and radiant.util.to_point3(sibling_spec.offset),
      destroy_on_remove = sibling_spec.destroy_on_remove,
      iconify_on_remove = sibling_spec.iconify_on_remove,
   }
   self._sv.siblings[entity:get_id()] = sibling
   self.__saved_variables:mark_changed()

   self:_create_sibling_predestroy_trace(entity)
   self:_update_sibling(sibling, mob:get_world_location(), mob:get_facing())
   self:_create_region_traces()

   if parent then
      radiant.entities.add_child(parent, entity)
   end

   return entity
end

function SiblingEntitiesComponent:remove_sibling(entity)
   self:_destroy_sibling(entity:get_id())
   self.__saved_variables:mark_changed()
end

function SiblingEntitiesComponent:_update_player_id()
   local player_id = radiant.entities.get_player_id(self._entity)
   for id, sibling in pairs(self._sv.siblings) do
      local entity = sibling.entity
      radiant.entities.set_player_id(entity, player_id)
   end
end

function SiblingEntitiesComponent:_remove_all_siblings_from_parent()
   for id, sibling in pairs(self._sv.siblings) do
      local entity = sibling.entity
      local parent = radiant.entities.get_parent(entity)
      if parent then
         radiant.entities.remove_child(parent, entity)
      end
   end
end

function SiblingEntitiesComponent:_add_all_siblings_to_parent()
   local mob = self._entity:get_component('mob')
   local parent = mob and mob:get_parent()
   if parent then
      self:_update_siblings()
      for id, sibling in pairs(self._sv.siblings) do
         local entity = sibling.entity
         radiant.entities.add_child(parent, entity)
      end
   end
end

function SiblingEntitiesComponent:_update_siblings(component_name)
   local mob = self._entity:get_component('mob')
   local parent = mob and mob:get_parent()
   if parent then
      local facing = mob:get_facing()
      local location = mob:get_world_location()
      for id, sibling in pairs(self._sv.siblings) do
         local entity = sibling.entity

         -- if we're updating a specific component, only update the sibling if it matches
         if not component_name or sibling.match_component_regions[component_name] then
            self:_update_sibling(sibling, location, facing, component_name)
         end
      end
   end
end

function SiblingEntitiesComponent:_update_sibling(sibling, location, facing, component_name)
   local entity = sibling.entity

   if location then
      if sibling.offset then
         location = radiant.entities.local_to_world(Cube3(sibling.offset), self._entity).min
      end

      radiant.entities.move_to(entity, location)
   end

   radiant.entities.turn_to(entity, facing)

   for component_name, match in pairs(sibling.match_component_regions) do
      if match and (not component_name or component_name == component_name) then
         local component = self._entity:get_component(component_name)
         if component then
            local sibling_component = entity:add_component(component_name)
            local region = sibling_component:get_region()
            if not region then
               region = radiant.alloc_region3()
               sibling_component:set_region(region)
            end

            -- since we want the region to mirror the parent's region, we need to adjust it based on location
            -- the sibling faces the same way, so we don't need to do local_to_world nonsense, just position offset
            -- **WARNING** destination region (and maybe others) DO NOT RESPECT NON-GRID LOCATIONS/OFFSETS
            local r = component:get_region():get()
            if sibling.offset then
               r = r:translated(-sibling.offset)
            end
            region:modify(function(cursor)
                  cursor:copy_region(r)
               end)
         end
      end
   end
end

return SiblingEntitiesComponent
