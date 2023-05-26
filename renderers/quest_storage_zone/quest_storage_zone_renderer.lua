local ZoneRenderer = require 'stonehearth.renderers.zone_renderer'

local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local QuestStorageZoneRenderer = class()

local log = radiant.log.create_logger('quest_storage_zone_renderer')

function QuestStorageZoneRenderer:initialize(render_entity, datastore)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._storage_point_nodes = {}
   self._datastore = datastore

   self._zone_renderer = ZoneRenderer(render_entity):set_ground_colors(Color4(55, 49, 26, 24), Color4(55, 49, 26, 32))

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)

   self._datastore_trace = self._datastore:trace_data('rendering stockpile designation')
      :on_changed(
         function()
            self:_update()
         end
      )
      :push_object_state()

   -- self._storage_point_render_trace = _radiant.client.trace_render_frame()
   --    :on_frame_finished('update storage point render nodes', function()
   --       for id, entity in pairs(self._new_entities) do
   --          self:_update_storage_point(entity, self._color)
   --       end
   --    end)
end

function QuestStorageZoneRenderer:destroy()
   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end

   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end

   self._zone_renderer:destroy()
   self:_destroy_storage_point_render_trace()
   self:_destroy_storage_points()
end

function QuestStorageZoneRenderer:_destroy_storage_point_render_trace()
   if self._storage_point_render_trace then
      self._storage_point_render_trace:destroy()
      self._storage_point_render_trace = nil
   end
end

function QuestStorageZoneRenderer:_destroy_storage_points()
   log:debug('destroying storage points')
   for _, node in ipairs(self._storage_point_nodes) do
      node:destroy()
   end
   self._storage_point_nodes = {}
end

function QuestStorageZoneRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update()
   end
end

function QuestStorageZoneRenderer:_update()
   local data = self._datastore:get_data()
   log:debug('data: %s', radiant.util.table_tostring(data))
   local c = Color4(unpack(data.zone_color or {153, 51, 255, 76}))
   self._zone_renderer:set_designation_colors(c, c)
   --self._zone_renderer:set_ground_colors(Color4(c.r, c.g, c.b, 32), Color4(c.r, c.g, c.b, 40))
   self._zone_renderer:set_size(data.size)
   self._zone_renderer:set_current_items(data.quest_storages)

   -- render fake/ghost storages where they would be
   self:_destroy_storage_points()

   local model_variants = radiant.entities.get_component_data(data.sample_container, 'model_variants')
   local model = model_variants and model_variants.default.models[1]

   if model and self._ui_view_mode == 'hud' then
      local render_info = radiant.entities.get_component_data(data.sample_container, 'render_info')
      local scale = render_info and render_info.scale or 0.1
      local mob = radiant.entities.get_component_data(data.sample_container, 'mob')
      local model_origin = (mob and radiant.util.to_point3(mob.model_origin) or Point3(0.5, 0, 0.5)) + Point3(1, 0, 1)
      local rotation = Point3(0, -data.rotation * 90, 0)

      for _, point in ipairs(data.points) do
         if not point.storage then
            log:debug('updating storage point at %s', point.location)
            local node = _radiant.client.create_qubicle_matrix_node(self._entity_node, model, 'Cuboid_1', model_origin / scale)
            if node then
               node:set_casts_shadows(false)
               node:set_can_query(false)
               node:set_scale(Point3.one * scale)
               node:set_rotation(rotation)
               node:set_position(point.location)
               node:set_material('materials/ghost_item.json', true)
               table.insert(self._storage_point_nodes, node)
            else
               log:error('%s error creating qubicle matrix node for model %s; requires matrix Cuboid_1', self._entity_node, model)
            end
         end
      end
   end
end

return QuestStorageZoneRenderer
