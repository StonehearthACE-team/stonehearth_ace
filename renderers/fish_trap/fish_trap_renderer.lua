local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local FishTrapRenderer = class()
local log = radiant.log.create_logger('fish_trap_renderer')

function FishTrapRenderer:initialize(render_entity, datastore)
   self._render_entity = render_entity
   self._datastore = datastore
   self._entity = self._render_entity:get_entity()
   self._parent_node = self._render_entity:get_node()

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)

   self._datastore_trace = self._datastore.__saved_variables:trace('rendering fish trap')
      :on_changed(function()
            log:debug('fish trap %s datastore changed', self._entity)
            self:_update()
         end
      )
      :push_object_state()
end

function FishTrapRenderer:destroy()
   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end

   if self._datastore_trace then
      self._datastore_trace:destroy()
      self._datastore_trace = nil
   end

   self:_destroy_water_region_node()
end

function FishTrapRenderer:_destroy_water_region_node()
   if self._water_region_node then
      self._water_region_node:destroy()
      self._water_region_node = nil
   end
end

function FishTrapRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_update()
   end
end

function FishTrapRenderer:_in_hud_mode()
   return self._ui_view_mode == 'hud'
end

function FishTrapRenderer:_update()
   self:_destroy_water_region_node()

   if not self:_in_hud_mode() then
      return
   end

   local data = self._datastore._sv or self._datastore:get_data()
   --log:debug('fish trap %s water_region = %s', self._entity, tostring(data.water_region))

   if data.water_region then
      self._water_region_node = _radiant.client.create_region_outline_node(RenderRootNode, data.water_region:inflated(Point3(0, 0.1, 0)),
               Color4(127, 0, 0, 160), Color4(127, 0, 0, 40), '/stonehearth/data/horde/materials/transparent_box_nodepth.material.json', 1)
            :set_casts_shadows(false)
            :set_can_query(false)
   end
end

return FishTrapRenderer
