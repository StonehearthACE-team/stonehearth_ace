local Point3 = _radiant.csg.Point3

local log = radiant.log.create_logger('decoration_tool')

local AceTemplatePlacementTool = class()

local function _test_template_placement(location, bounds, bc, delta_fixup, rotation)
   bounds = bounds:translated(location)
   local do_fine_check = false
   local overlapping = radiant.terrain.get_entities_in_cube(bounds)
   for _, overlap in pairs(overlapping) do
      if radiant.entities.is_solid_entity(overlap) or
            radiant.entities.get_entity_data(overlap, 'stonehearth:designation') or
            radiant.entities.get_entity_data(overlap, 'stonehearth:build2:blueprint') then
         do_fine_check = true
         break
      end
   end

   if do_fine_check then
      local region = bc:get_region():rotated(360 - rotation):translated(location - delta_fixup)
      local found = true

      local overlapping = radiant.terrain.get_entities_in_region(region)
      for _, overlap in pairs(overlapping) do
         local designation = radiant.entities.get_entity_data(overlap, 'stonehearth:designation')
         if radiant.entities.is_solid_entity(overlap) or
               (designation and not designation.allow_templates) or
               radiant.entities.get_entity_data(overlap, 'stonehearth:build2:blueprint') then
            found = false
            break
         end
      end
      if not found then
         return false
      end
   end
   return true
end

function AceTemplatePlacementTool:_place_template(brick)
   local bc = self._temp_building:get('stonehearth:build2:temp_building')

   local do_fine_check = false
   local bounds = bc:get_bounds()
   local b_size = bounds:get_size()

   bounds = bounds:rotated(360 - self._rotation)

   local delta_fixup = Point3(0, 0, 0)
   local rot_delta = 360 - self._rotation
   if rot_delta == 90 then
      delta_fixup = Point3(0, 0, -1)
   elseif rot_delta == 180 then
      delta_fixup = Point3(-1, 0, -1)
   elseif rot_delta == 270 then
      delta_fixup = Point3(-1, 0, 0)
   end

   bounds = bounds:translated(-delta_fixup)

   local found = true
   if not _test_template_placement(brick, bounds, bc, delta_fixup, self._rotation) then
      found = false

      if self._pos then
         local last_delta = brick - self._pos
         local dir = nil

         if math.abs(last_delta.x) > math.abs(last_delta.z) then
            dir = Point3(last_delta.x, 0, 0)
         else
            dir = Point3(0, 0, last_delta.z)
         end
         brick = self._pos + dir
         dir:normalize()
         dir = -dir

         for i=1,10 do
            if _test_template_placement(brick, bounds, bc, delta_fixup, self._rotation) then
               found = true
               break
            end
            brick = brick + dir
         end
      end
   end

   if not found then
      return
   end

   self._pos = brick

   self._render_entity:set_position(self._pos + self._sink_offset)
   self._render_entity:set_rotation(Point3(0, 360 - self._rotation, 0))
end

return AceTemplatePlacementTool
