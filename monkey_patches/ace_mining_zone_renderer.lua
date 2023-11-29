local Point3 = _radiant.csg.Point3
local Color4 = _radiant.csg.Color4

local AceMiningZoneRenderer = class()

function AceMiningZoneRenderer:_get_color(is_enabled, bid)
   local suspended_mult = is_enabled and 1 or 0.4
   local color
   if stonehearth.presence_client:is_multiplayer() then
      color = stonehearth.presence_client:get_player_color(radiant.entities.get_player_id(self._entity))
   else
      color = Point3(255, 255, 0)
   end

   if bid then
      -- if it's part of a building id, reduce the green
      color.y = color.y * 0.8
   end
   return color * suspended_mult
end

function AceMiningZoneRenderer:_in_visible_mode()
   return self._ui_view_mode == 'hud' or self._ui_view_mode == 'build'
end

function AceMiningZoneRenderer:_update()
   self:_destroy_outline_node()

   if not self:_in_visible_mode() then
      self._boxed_region:modify(function(cursor)
            cursor:clear()
         end)
      return
   end

   -- Believe it or not, doing this in the initializer isn't correct, as
   -- apparently the root might not exist (on load!)
   -- This is basically free, though, so just set the cut on every update.
   _radiant.renderer.add_terrain_cut(self._boxed_region)

   local location = radiant.entities.get_world_grid_location(self._entity)
   local data = self._datastore:get_data()
   local working_region = data.region:get():translated(location)
   local completed = radiant.terrain.clip_region(working_region)

   self._boxed_region:modify(function(cursor)
         cursor:copy_region(working_region)
      end)

   working_region = stonehearth.subterranean_view:intersect_region_with_visible_volume(working_region)
   working_region = working_region - completed
   working_region:optimize('mining zone renderer')
   working_region = working_region:inflated(Point3(0.001, 0.001, 0.001))  -- Puff it out so there's a floating region.

   working_region:translate(-location)

   local color = self:_get_color(data.enabled, data.bid)

   local EDGE_COLOR_ALPHA = 24
   local FACE_COLOR_ALPHA = 8
   local render_node = _radiant.client.create_region_outline_node(self._parent_node, working_region, radiant.util.to_color4(color, EDGE_COLOR_ALPHA), radiant.util.to_color4(color, FACE_COLOR_ALPHA), 'materials/transparent_box_nodepth.material.json', 'materials/debug_shape_nodepth.material.json', 0)
   local face_render_node = _radiant.client.create_region_outline_node(RenderRootNode, working_region, radiant.util.to_color4(color, EDGE_COLOR_ALPHA * 8), radiant.util.to_color4(color, FACE_COLOR_ALPHA * 5), 'materials/transparent_box.material.json', 'materials/debug_shape.material.json', 0)
   face_render_node:set_parent(render_node)
   render_node:add_reference_to(face_render_node)
   self._outline_node = render_node

   stonehearth.selection:set_selectable(self._entity, data.selectable)
end

return AceMiningZoneRenderer
