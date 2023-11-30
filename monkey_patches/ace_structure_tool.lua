local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local Point2 = _radiant.csg.Point2
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local Ray3 = _radiant.csg.Ray3

local AceStructureTool = class()

function AceStructureTool:_on_start(e)
   local thing = self:_selection_under_mouse(e.x, e.y, true)
   -- Cursor disappears if we have no place.
   -- POSSIBILITY: find the closest point...somewhere?...to place us.
   if not thing then
      stonehearth.debug_shapes:destroy_box(self._boxid)
      return
   end

   local start_pt = thing.brick
   local normal = thing.normal

   if not self._intersectable_structures[thing.entity:get_uri()] then
      if self._snap_to_top then
         if thing.entity:get_id() == radiant._root_entity_id then
            if normal ~= Point3(0, 1, 0) then
               stonehearth.debug_shapes:destroy_box(self._boxid)
               return
            end
         else
            start_pt = thing.brick
            local r = radiant.entities.get_world_region(thing.entity)

            local testpt = Point3(0, 1, 0)
            while r:contains(start_pt) do
               start_pt = start_pt + testpt
            end

            normal = Point3(0, 1, 0)
         end
      end
   else
      if self._snap_to_top then
         normal = Point3(0, 1, 0)
      end
   end

   if self._always_on_top then
      start_pt = start_pt + normal
   elseif thing.entity:get_uri() == 'stonehearth:build2:editor:entities:room' then
      start_pt = start_pt + Point3(0, self._floor_offset, 0)
   elseif thing.entity:get_id() == radiant._root_entity_id then
      start_pt = start_pt + Point3(0, self._terrain_offset, 0)
   end

   local c = _radiant.csg.from_points(start_pt, start_pt)

   local invalid_es = radiant.terrain.get_entities_at_point(start_pt, function(e)
         return e:get_uri() == 'stonehearth:build2:entities:envelope'
      end)

   if not radiant.empty(invalid_es) then
      return
   end

   self._boxid = stonehearth.debug_shapes:show_box(Region3(c:translated(self._terrain_cut_offset)), self._color, nil, {
      box_id = self._boxid,
      material = self._material,
   })

   if e:down(1) then
      local data, pt = self._start_placing_cb(start_pt, normal)
      self._data = data
      start_pt = pt or start_pt

      self._blueprint = radiant.entities.create_entity(self._bp_uri)
      self._bp_c = self._blueprint:get('stonehearth:build2:blueprint')
      self._bp_c:init(self._data)

      stonehearth.building:add_blueprint(self._blueprint)

      self._widget = radiant.entities.create_entity(self._widget_uri)
      self._widget:get(self._widget_component):from_blueprint(self._bp_c)

      if self._hold_to_drag_only then
         self._state = 'dragging'
      else
         self._state = 'first_mouse_down'
      end
      self._start = start_pt
      self._end = start_pt
      self._normal = normal
      self._start_screen_point = Point2(e.x, e.y)

      -- Bias for rounding, so that we get our blocks in the right position.
      local nabs = radiant.math.abs_point3(self._normal)
      local reversen = Point3(1, 1, 1) - nabs
      self._bias = Point3(0, -0.5 * reversen.y, 0)

   end
end

return AceStructureTool
