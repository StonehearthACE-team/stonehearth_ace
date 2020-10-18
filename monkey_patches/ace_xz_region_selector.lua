local Point2 = _radiant.csg.Point2
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3

local XZRegionSelector = require 'stonehearth.services.client.selection.xz_region_selector'
local AceXZRegionSelector = class()

local log = radiant.log.create_logger('xz_region_selector')

local INTERSECTION_NODE_NAME = 'xz region selector intersection node'
local MAX_RESONABLE_DRAG_DISTANCE = 512
local MODEL_OFFSET = Point3(-0.5, 0, -0.5)

AceXZRegionSelector._ace_old___init = XZRegionSelector.__user_init
function AceXZRegionSelector:__init(reason)
   self:_ace_old___init(reason)

   self._create_intersection_node = true
   self._reset_on_invalid_region = true
end

function AceXZRegionSelector:set_create_intersection_node(create_it)
   self._create_intersection_node = create_it
   return self
end

function AceXZRegionSelector:set_reset_on_invalid_region(reset)
   self._reset_on_invalid_region = reset
   return self
end

function AceXZRegionSelector:_run_p0_selected_state(event, brick, normal)
   -- make a new entity that we can use to find the position of the mouse
   -- at the same height that we started.
   if self._create_intersection_node and not self._intersection_node then
      local y = self._p0.y
      local d = MAX_RESONABLE_DRAG_DISTANCE
      local cube = Cube3(self._p0):inflated(Point3(d, 0, d))
      local region = Region3(cube)

      if self._select_front_brick then
         region:translate(Point3(0, -1, 0))
      end

      self._intersection_node = _radiant.client.create_voxel_node(RenderRootNode, region, '', MODEL_OFFSET)
                                                   :set_name(INTERSECTION_NODE_NAME)
                                                   :set_visible(false)
                                                   :set_can_query(true)
   end

   if stonehearth.selection.user_cancelled(event) then
      self._action = 'reject'
      return 'stop'
   end

   -- avoid spamming recalculcation and update if nothing has changed
   if brick == self._last_brick and not event:up(1) then
      self._action = nil
      return 'p0_selected'
   end

   local q0, q1 = self:_resolve_endpoints(self._p0, brick, self._stabbed_normal)

   if not q0 or not q1 then
      -- maybe the world has changed after we started dragging
      log:error('unable to resolve endpoints: %s, %s', tostring(q0), tostring(q1))
      return 'p0_selected'
   end

   self._p0, self._p1 = q0, q1

   if event:up(1) then
      -- Make sure our cache still reflects the current state of the world.
      -- Note we still have a short race condition with the server as the state
      -- may have changed there which is not yet reflected on the client.
      self._valid_region_cache:clear()
      local q0, q1 = self:_find_valid_region(self._p0, self._p1)
      local is_valid_region = q0 == self._p0 and q1 == self._p1

      if is_valid_region and self:_are_valid_dimensions(self._p0, self._p1) then
         self._action = 'resolve'
      elseif self._reset_on_invalid_region then
         self._p0, self._p1 = nil, nil
         return 'start'
      else
         self._action = 'reject'
      end
      return 'stop'
   else
      return 'p0_selected'
   end
end

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
