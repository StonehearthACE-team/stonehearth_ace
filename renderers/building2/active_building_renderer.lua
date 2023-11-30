local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Region3 = _radiant.csg.Region3
local Color4 = _radiant.csg.Color4

local IN_DESIGN_COLOR = Color4(86, 193, 220, 255)
local IN_PLAN_COLOR = Color4(236, 224, 0, 255)
local IN_BUILD_COLOR = Color4(32, 192, 64, 255)
local INVISIBLE_COLOR = Color4(0, 0, 0, 0)

local csg_lib = require 'stonehearth.lib.csg.csg_lib'

local ActiveBuildingRenderer = class()
local log = radiant.log.create_logger('building.active_renderer')

function ActiveBuildingRenderer:initialize(render_entity, active_building)
   self._entity = render_entity:get_entity()
   self._entity_node = render_entity:get_node()
   self._active_building = active_building.__saved_variables
   self._outline_nodes = {}
   render_entity:add_query_flag(_radiant.renderer.QueryFlags.UNSELECTABLE)
   self._region = Region3()
   self._old_color = IN_DESIGN_COLOR
   self._always_show_unfinished_regions = stonehearth_ace.gameplay_settings:get_gameplay_setting('stonehearth_ace', 'always_show_building_blueprint_regions')
   self._show = self:_should_show(self._active_building:get_data())
   self._setting_listener = radiant.events.listen(radiant, 'always_show_building_blueprint_regions_setting_changed', function(show)
         self._always_show_unfinished_regions = show
         self:_update_shape()
      end)
   self._building_promise = self._active_building:trace_data('drawing active building')
                                          :on_changed(function ()
                                                self:_update_shape()
                                             end)
                                          :push_object_state()
end

function ActiveBuildingRenderer:destroy()
   if self._building_promise then
      self._building_promise:destroy()
      self._building_promise = nil
   end
   if self._setting_listener then
      self._setting_listener:destroy()
      self._setting_listener = nil
   end

   for _, n in pairs(self._outline_nodes) do
      n:destroy()
   end
   self._outline_nodes = {}
end

function ActiveBuildingRenderer:_should_show(data)
   return data.is_active or (self._always_show_unfinished_regions and data.building_status ~= stonehearth.constants.building.building_status.FINISHED)
end

function ActiveBuildingRenderer:_update_shape()
   local data = self._active_building:get_data()
   local region = data.support_region
   local status = data.building_status
   local player_id = data.player_id
   local show = self:_should_show(data)
   local show_player_color = player_id ~= _radiant.client.get_player_id()
   local player_color

   if show_player_color then
      player_color = stonehearth.presence_client:get_player_color(player_id)
      player_color = radiant.util.to_color4(player_color, 255)
   end

   local color = IN_DESIGN_COLOR
   if status == stonehearth.constants.building.building_status.BUILDING then
      color = IN_BUILD_COLOR
   elseif status == stonehearth.constants.building.building_status.PLANNING then
      color = IN_PLAN_COLOR
   end

   if not self._region:equals(region) or self._old_color:to_integer() ~= color:to_integer() then
      self._old_color = color
      self._region = region:duplicate()
      for _, n in ipairs(self._outline_nodes) do
         n:destroy()
      end

      self._outline_nodes = {}
      for _, r in ipairs(csg_lib.get_contiguous_regions(region)) do
         local y = r:get_bounds().max.y - 1
         r = r:project_onto_xz_plane()
         local n = _radiant.client.create_designation_node(self._entity_node, r,
                                        color, INVISIBLE_COLOR)
         n:set_position(Point3(0, y, 0))
         n:set_visible(show)
         n:set_can_query(false)

         if show_player_color then
            r = r:inflated(Point2(1, 1))
            local player_color_outline_node = _radiant.client.create_region2_outline_node(self._entity_node, r, player_color)
            player_color_outline_node:set_position(Point3(0, y + 0.01, 0))
            player_color_outline_node:set_visible(show)
            player_color_outline_node:set_can_query(false)
            table.insert(self._outline_nodes, player_color_outline_node)
         end

         table.insert(self._outline_nodes, n)
      end
   end

   if self._show ~= show then
      self._show = show
      for _, o in ipairs(self._outline_nodes) do
         o:set_visible(self._show)
         o:set_can_query(false)
      end
   end
end

return ActiveBuildingRenderer

