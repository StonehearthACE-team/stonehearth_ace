local Point3 = _radiant.csg.Point3
local build_util = require 'lib.build_util'
local StructureEditor = radiant.mods.require('stonehearth.services.client.build_editor.structure_editor')
local HatchEditor = class(StructureEditor)

local log = radiant.log.create_logger('build_editor')

function HatchEditor:__init(build_service)
   self[StructureEditor]:__init()
   self._build_service = build_service
end

function HatchEditor:destroy()
   stonehearth.selection:register_tool(self, false)

   if self._fixture_blueprint then
      radiant.entities.destroy_entity(self._fixture_blueprint)
      self._fixture_blueprint = nil
   end

   if self._fixture_blueprint_visibility_handle then
      self._fixture_blueprint_visibility_handle:destroy()
      self._fixture_blueprint_visibility_handle = nil
   end

   if self._cursor then
      self._cursor:destroy()
      self._cursor = nil
   end

   if self._invalid_cursor then
      self._invalid_cursor:destroy()
      self._invalid_cursor = nil
   end

   if self._capture then
      self._capture:destroy()
      self._capture = nil
   end

   self[StructureEditor]:destroy()
end

function HatchEditor:set_fixture_uri(fixture_uri)
   local data = radiant.entities.get_component_data(fixture_uri, 'stonehearth:entity_forms')

   assert(data, 'hatches must also have all 3 entity forms')
   assert(data.iconic_form, 'hatch missing iconic entity form')
   assert(data.ghost_form, 'hatch missing ghost entity form')

   self._fixture_uri = fixture_uri
   self._fixture_iconic_uri = data.iconic_form
   self._fixture_blueprint_uri = data.ghost_form

   return self
end

function HatchEditor:set_fixture_quality(quality)
   self._fixture_quality = quality

   return self
end

function HatchEditor:go(response)
   self._response = response
   self._fixture_blueprint = radiant.entities.create_entity(self._fixture_blueprint_uri)
   self._fixture_blueprint:add_component('render_info')
                              :set_material('materials/ghost_item.json')
   self._cursor_uri = self._fixture_blueprint:get_component('stonehearth:fixture')
                                                      :get_cursor()
   if not self._cursor_uri then
      self._cursor_uri = 'stonehearth:cursors:arrow'
   end

   self._fixture_blueprint_render_entity = _radiant.client.create_render_entity(RenderRootNode, self._fixture_blueprint)
   self._fixture_blueprint_render_entity:set_parent_override(false)

   self._fixture_blueprint_visibility_handle = self._fixture_blueprint_render_entity:get_visibility_override_handle()
   self._fixture_blueprint_visibility_handle:set_visible(false)
   self._invalid_cursor = _radiant.client.set_cursor('stonehearth:cursors:invalid_hover')
   self._capture = stonehearth.input:capture_input('HatchEditor')
                                          :on_mouse_event(function(e)
                                                return self:_on_mouse_event(e)
                                             end)
   stonehearth.selection:register_tool(self, true)
   return self
end

function HatchEditor:_ignore_entity(entity)
   if not entity or not entity:is_valid() then
      return true
   end

   if not stonehearth.selection:is_selectable(entity) then
      return true
   end

   return false
end

function HatchEditor:_clear_hatch_portal()
   if self._proxy_floor then
      self._fixture_blueprint_visibility_handle:set_visible(false)
      self._proxy_floor:remove_fixture(self._fixture_blueprint)
      self._proxy_floor = nil
      self._old_location = nil
   end
end

function HatchEditor:_on_mouse_event(e, selection)
   if stonehearth.selection.user_cancelled(e) then
      self:destroy()
      return true
   end

   local raycast_results = _radiant.client.query_scene(e.x, e.y)
   local entity, fabricator, blueprint, project
   local found_floor = false

   -- look for a valid floor
   for result in raycast_results:each_result() do
      entity = result.entity
      local ignore_entity = self:_ignore_entity(entity)

      if not ignore_entity then
         log:detail('hit entity %s', entity)

         fabricator, blueprint, project = build_util.get_fbp_for(entity)

         if blueprint then
            found_floor = blueprint:get_component('stonehearth:floor')
            break
         end
      end
   end

   if found_floor then
      if not self._proxy_floor or not self:should_keep_focus(entity) then
         self:_clear_hatch_portal()
         self:reset_editing()
         self:begin_editing(fabricator, blueprint, project, 'stonehearth:floor')
         self._proxy_blueprint = self:get_proxy_blueprint()
         self._proxy_floor = self._proxy_blueprint:get_component('stonehearth:floor')
      end

      local location
      local proxy_fabricator = self:get_proxy_fabricator()
      for result in raycast_results:each_result() do
         if result.entity == proxy_fabricator then
            location = result.brick
            break
         end
      end
      if location then
         self:_position_fixture(location)
      end
   else
      if self._proxy_floor then
         self:_clear_hatch_portal()
         self:_change_cursor('stonehearth:cursors:invalid_hover')
         self:reset_editing()
      end
   end

   if e:up(1) then
      self:submit(self._response)
      self:destroy()
   end

   local event_consumed = e and (e:down(1) or e:up(1))
   return event_consumed
end

function HatchEditor:_position_fixture(location)
   -- convert to local coordinates
   location = location - self:get_world_origin()

   local location = self:get_proxy_blueprint()
                           :get_component('stonehearth:floor')
                              :compute_fixture_placement(self._fixture_blueprint, location)

   if location and self._old_location ~= location then
      self._fixture_blueprint_visibility_handle:set_visible(true)
      self:_change_cursor(self._cursor_uri)
      self._proxy_floor:add_fixture(self._fixture_blueprint, location)
      self._proxy_floor:layout()
   end
   self._old_location = location
end

function HatchEditor:_change_cursor(uri)
   if self._installed_cursor_uri ~= uri then
      if self._cursor then
         self._cursor:destroy()
         self._cursor = nil
      end
      if uri then
         self._cursor = _radiant.client.set_cursor(uri)
      end
      self._installed_cursor_uri = uri
   end
end

function HatchEditor:submit()
   local mob = self._fixture_blueprint and self._fixture_blueprint:get_component('mob')
   local parent = mob and mob:get_parent()

   if not parent then
      self._response:reject('invalid fixture location')
      return
   end

   local location = mob:get_grid_location()

   _radiant.call_obj(self._build_service, 'add_fixture_command', self:get_blueprint(), self._fixture_uri, self._fixture_quality, location)
      :done(function(r)
            self._response:resolve(r)
         end)
      :fail(function(r)
            self._response:reject(r)
         end)
end

return HatchEditor
