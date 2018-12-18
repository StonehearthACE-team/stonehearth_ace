local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local constants = require 'stonehearth.constants'

local FarmerFieldRenderer = require 'stonehearth.renderers.farmer_field.farmer_field_renderer'
local AceFarmerFieldRenderer = class()

AceFarmerFieldRenderer._old_initialize = FarmerFieldRenderer.initialize
function AceFarmerFieldRenderer:initialize(render_entity, datastore)
   self:_old_initialize(render_entity, datastore)

   self._water_color = Color4(constants.hydrology.DEFAULT_WATER_COLOR)

   self._ui_view_mode = stonehearth.renderer:get_ui_mode()
   self._ui_mode_listener = radiant.events.listen(radiant, 'stonehearth:ui_mode_changed', self, self._on_ui_mode_changed)
end

AceFarmerFieldRenderer._old_destroy = FarmerFieldRenderer.destroy
function FarmerFieldRenderer:destroy()
   self:_old_destroy()

   if self._ui_mode_listener then
      self._ui_mode_listener:destroy()
      self._ui_mode_listener = nil
   end

   if self._water_signal_region_node then
      self._water_signal_region_node:destroy()
      self._water_signal_region_node = nil
   end
end

AceFarmerFieldRenderer._old__update = FarmerFieldRenderer._update
function FarmerFieldRenderer:_update()
   self:_old__update()

   self:_render_water_signal_region()
end

function AceFarmerFieldRenderer:_on_ui_mode_changed()
   local mode = stonehearth.renderer:get_ui_mode()

   if self._ui_view_mode ~= mode then
      self._ui_view_mode = mode

      self:_render_water_signal_region()
   end
end

function AceFarmerFieldRenderer:_in_appropriate_mode()
   return self._ui_view_mode == 'hud'
end

function AceFarmerFieldRenderer:_render_water_signal_region()
   if self._water_signal_region_node then
      self._water_signal_region_node:destroy()
      self._water_signal_region_node = nil
   end

   if not self:_in_appropriate_mode() then
      return
   end

   local data = self._datastore:get_data()
   local region = data.water_signal_region
   if region then
      local material = '/stonehearth/data/horde/materials/transparent_box_nodepth.material.json'
      self._water_signal_region_node = _radiant.client.create_region_outline_node(self._entity_node, region:inflated(Point3(-0.05, -0.05, -0.05)),
            self._water_color, Color4(0, 0, 0, 0), material, 1)
         :set_casts_shadows(false)
         :set_can_query(false)
   end
end

return AceFarmerFieldRenderer
