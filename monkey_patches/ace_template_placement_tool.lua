local Point3 = _radiant.csg.Point3
local bindings = _radiant.client.get_binding_system()
local build_util = require 'stonehearth.lib.build_util'

local log = radiant.log.create_logger('template_placement_tool')

local TemplatePlacementTool = require 'stonehearth.services.client.building.template_placement_tool'
local AceTemplatePlacementTool = class()

local function is_shift_held()
   return _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_LEFT_SHIFT)
       or _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_RIGHT_SHIFT)
end

function AceTemplatePlacementTool:_on_keyboard_event(e)
   local event_consumed = false
   local deltaRot = 0
   local sink = nil
   local grid_changed = false
   local pos = self._pos

   -- period and comma rotate the cursor
   if bindings:is_action_active('build:rotate:left') then
      deltaRot = -90
   elseif bindings:is_action_active('build:rotate:right') then
      deltaRot = 90
   end

   if bindings:is_action_active('build:sink_template') then
      sink = true
   elseif bindings:is_action_active('build:raise_template') then
      sink = false
   end

   if sink ~= nil then
      if sink then
         self._sink_offset = Point3(0, -1, 0)
      else
         self._sink_offset = Point3(0, 0, 0)
      end
   end

   if e.key == _radiant.client.KeyboardInput.KEY_LEFT_SHIFT or e.key == _radiant.client.KeyboardInput.KEY_RIGHT_SHIFT then
      self._pos = nil
      pos = self._raw_pos
      if pos and e.down then
         pos = self:_get_snap_grid_position(pos)
      end

      grid_changed = true
   end

   if deltaRot ~= 0 or sink ~= nil or grid_changed then
      self._rotation = (360 + ((self._rotation + deltaRot) % 360)) % 360

      if pos then
         self:_place_template(pos)
         build_util:play_rotate_sound()
      end
      event_consumed = true
   end

   return event_consumed
end

-- ACE: add snap-to-grid capability
-- TODO: also render corresponding grid on terrain? then need to clean up in _self_destruct function
-- that might be a *lot* of lines, especially if the grid is small
function AceTemplatePlacementTool:_calculate_stab_point(p)
   local results = _radiant.client.query_scene(p.x, p.y)

   for r in results:each_result() do
      -- TODO: templates on existing structures should be okay.
      if r.entity and r.entity:get_id() == radiant._root_entity_id and r.normal.y == 1 then
         -- ACE: if snap to grid enabled, snap the result to that x/z grid
         local brick = r.brick + r.normal
         self._raw_pos = brick
         if is_shift_held() then
            brick = self:_get_snap_grid_position(brick)
         end

         return brick, r.entity, r.normal
      end
   end

   return nil, nil, nil
end

function AceTemplatePlacementTool:_get_snap_grid_position(pos)
   local grid = self._snap_grid_size
   local size = self._size
   if not grid then
      grid = stonehearth_ace.gameplay_settings:get_gameplay_setting('stonehearth_ace', 'building_grid_size')
      self._snap_grid_size = grid
   end
   if not size then
      local bc = self._temp_building:get('stonehearth:build2:temp_building')
      size = bc:get_bounds():get_size()
      self._size = size
   end

   -- WHY?!?!
   local delta_fixup = Point3(0, 0, 0)
   local rot_delta = 360 - self._rotation
   if rot_delta == 90 then
      delta_fixup = Point3(0, 0, -1)
   elseif rot_delta == 180 then
      delta_fixup = Point3(-1, 0, -1)
   elseif rot_delta == 270 then
      delta_fixup = Point3(-1, 0, 0)
   end

   -- set up shift based on size and rotation
   local center_shift = size:rotated(360 - self._rotation)
   center_shift = Point3(math.abs(math.floor(center_shift.x / 2 + 0.5)), 0, math.abs(math.floor(center_shift.z / 2 + 0.5))) + delta_fixup
   log:debug('from bounds size %s rotated %s shifted by %s to %s', size, self._rotation, delta_fixup, center_shift)

   -- round to nearest grid dimensions
   local dest = pos - center_shift
   dest.x = math.floor(dest.x / grid + 0.5) * grid
   dest.z = math.floor(dest.z / grid + 0.5) * grid

   log:debug('converting %s to grid point %s', pos, dest + center_shift)

   return dest + center_shift
end

-- ACE: allow placement on designations that specifically allow_templates
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

         for i = 1, 10 do
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
