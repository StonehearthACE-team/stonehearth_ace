local Point2 = _radiant.csg.Point2
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2

local AceXZRegionSelector = class()

function AceXZRegionSelector:_update_selected_cube(box)
   if self._render_node then
      self._render_node:destroy()
      self._render_node = nil
   end

   self._region_shape = nil

   if not box then
      return
   end

   if self._create_marquee_fn then
      self._render_node, self._region_shape, self._region_type = self._create_marquee_fn(self, box, self._p0, self._stabbed_normal)
      if not self._region_type then
         self._region_type = 'Region3'
      end
   elseif self._create_node_fn then
      -- save these to be sent to the presence service to render on other players' clients
      self._region_shape = box
      self._region_type = 'Region2'
      -- recreate the render node for the designation
      local size = box:get_size()
      local region = Region2(Rect2(Point2.zero, Point2(size.x, size.z)))
      self._render_node = self._create_node_fn(RenderRootNode, region, self._box_color, self._line_color)
                                    :set_position(box.min)
   end

   -- Why would we want a selectable cursor?  Because we're querying the actual displayed objects, and when
   -- laying down floor, we cut into the actual displayed object.  So, you select a piece of terrain, then cut
   -- into it, and then you move the mouse a smidge.  Now, the query goes through the new hole, hits another
   -- terrain block, and the hole _moves_ to the new selection; nudge the mouse again, and the hole jumps again.
   -- Outside of re-thinking the way selection works, this is the only fix that occurs to me.
   if self._render_node then  -- ACE: just added this conditional so a custom marquee doesn't need to return one
      self._render_node:set_can_query(self._allow_select_cursor)
   end
end

return AceXZRegionSelector
