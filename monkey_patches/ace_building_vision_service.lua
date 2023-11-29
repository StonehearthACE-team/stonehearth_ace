local AceBuildingVisionService = class()

local log = radiant.log.create_logger('building_vision_service')

function AceBuildingVisionService:update_template_tool_terrain_cut(region)
   log:spam('_update_terrain_cut for template tool')
   if self._template_tool_terrain_cut then
      if not region then
         _radiant.renderer.remove_terrain_cut(self._template_tool_terrain_cut)
         self._template_tool_terrain_cut = nil
         return
      end
   elseif region then
      self._template_tool_terrain_cut = radiant.alloc_region3()
      _radiant.renderer.add_terrain_cut(self._template_tool_terrain_cut)
   else
      return
   end

   self._template_tool_terrain_cut:modify(function(cursor)
      cursor:clear()
      cursor:add_region(region)
   end)
end

function AceBuildingVisionService:_update_terrain_cut(bid, widget)
   log:spam('_update_terrain_cut for %s', widget)
   local origin = radiant.entities.get_world_grid_location(widget)
   local shape_w = widget:get('destination'):get_region():get()
   local room_widget = widget:get('stonehearth:build2:room_widget')
   if room_widget then
      shape_w = room_widget:get_data().region
   end
   shape_w = shape_w:translated(origin)

   local terrain_cut = self.terrain_cuts[bid]
   if not terrain_cut then
      terrain_cut = radiant.alloc_region3()
      self.terrain_cuts[bid] = terrain_cut

      if stonehearth.renderer:get_ui_mode() == 'build' then
         _radiant.renderer.add_terrain_cut(terrain_cut)
      end
   end

   local bounds = shape_w:get_bounds()
   local r = shape_w:project_onto_xz_plane():lift(bounds.min.y, bounds.max.y)
   if not radiant.terrain.region_intersects_terrain(r) then
      terrain_cut:modify(function(cursor)
            cursor:clear()
         end)
      return
   end

   terrain_cut:modify(function(cursor)
         cursor:clear()
         cursor:add_region(r) -- shape_w:peel(Point3(0, 1, 0))
      end)
end

return AceBuildingVisionService
