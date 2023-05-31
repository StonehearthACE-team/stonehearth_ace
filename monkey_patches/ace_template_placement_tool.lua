local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local bindings = _radiant.client.get_binding_system()
local build_util = require 'stonehearth.lib.build_util'
local BlockWidgetUris = {
   ['stonehearth:build2:entities:blocks_widget'] = 'stonehearth:build2:blocks_widget',
   ['stonehearth:build2:entities:perimeter_wall_widget'] = 'stonehearth:build2:perimeter_wall_widget',
   ['stonehearth:build2:entities:road_widget'] = 'stonehearth:build2:road_widget',
   ['stonehearth:build2:entities:roof_perimeter_wall_widget'] = 'stonehearth:build2:perimeter_wall_widget',
   ['stonehearth:build2:entities:roof_widget'] = 'stonehearth:build2:roof_widget',
   ['stonehearth:build2:entities:room_widget'] = 'stonehearth:build2:room_widget',
   ['stonehearth:build2:entities:wall_widget'] = 'stonehearth:build2:wall_widget',
}
local StructureUri = 'stonehearth:build2:entities:structure'

local log = radiant.log.create_logger('template_placement_tool')

local TemplatePlacementTool = require 'stonehearth.services.client.building.template_placement_tool'
local AceTemplatePlacementTool = class()

local function is_ctrl_held()
   return _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_LEFT_CONTROL)
       or _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_RIGHT_CONTROL)
end

local function _is_owning_building_finished(building)
   local building_comp = building and building:get_player_id() == _radiant.client.get_player_id() and building:get_component('stonehearth:build2:building')
   return building_comp and building_comp._sv.building_status == stonehearth.constants.building.building_status.FINISHED
end

local function _is_widget_finished(widget_comp)
   local building_id = widget_comp and widget_comp:get_data():get_building_id()
   local building = building_id and stonehearth.building:get_building(building_id)
   return building and _is_owning_building_finished(building)
end

function AceTemplatePlacementTool:_on_keyboard_event(e)
   local event_consumed = false
   local deltaRot = 0
   local sink = nil
   local grid_changed = false
   local pos = self._pos
   local grid_offset_change = Point2(0, 0)
   local grid_offset_changed = false

   if not self._grid_offset then
      self._grid_offset = stonehearth.building:get_build_grid_offset()
   end

   -- period and comma rotate the cursor
   if bindings:is_action_active('build:rotate:left') then
      deltaRot = -90
   elseif bindings:is_action_active('build:rotate:right') then
      deltaRot = 90
   elseif bindings:is_action_active('build:sink_template') then
      sink = true
   elseif bindings:is_action_active('build:raise_template') then
      sink = false
   elseif bindings:is_action_active('build:grid_offset_minus_x') then
      grid_offset_change.x = -1
   elseif bindings:is_action_active('build:grid_offset_plus_x') then
      grid_offset_change.x = 1
   elseif bindings:is_action_active('build:grid_offset_minus_z') then
      grid_offset_change.y = -1
   elseif bindings:is_action_active('build:grid_offset_plus_z') then
      grid_offset_change.y = 1
   end

   if sink ~= nil then
      if sink then
         self._sink_offset = Point3(0, -1, 0)
      else
         self._sink_offset = Point3(0, 0, 0)
      end
   end

   if grid_offset_change ~= Point2.zero then
      grid_offset_changed = true
      local grid_offset = self._grid_offset + grid_offset_change
      self._grid_offset = Point2(grid_offset.x % 16, grid_offset.y % 16)
      log:spam('grid offset is now %s', self._grid_offset)
      stonehearth.building:set_build_grid_offset(self._grid_offset)
   end

   if is_ctrl_held() then
      self._pos = nil
      pos = self._raw_pos
      if pos then
         pos = self:_get_snap_grid_position(pos)
         log:spam('adjusted snap grid position from %s to %s', self._raw_pos, pos)
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

function AceTemplatePlacementTool:_commit()
   if not self._pos then
      return
   end

   local sunk_pos = self:_get_sunk_position()

   local bc = self._temp_building:get('stonehearth:build2:temp_building')
   stonehearth.building:place_building(
      bc:get_template_id(),
      sunk_pos + bc:get_offset(),
      sunk_pos,
      self._rotation)
end

-- ACE: add snap-to-grid capability
-- TODO: also render corresponding grid on terrain? then need to clean up in _self_destruct function
-- that might be a *lot* of lines, especially if the grid is small
function AceTemplatePlacementTool:_calculate_stab_point(p)
   local results = _radiant.client.query_scene(p.x, p.y)

   for r in results:each_result() do
      if r.entity and r.normal.y == 1 then
         -- make sure the entity is the root entity or a completed building's structure
         local valid_entity = r.entity:get_id() == radiant._root_entity_id
         local widget_comp_uri = BlockWidgetUris[r.entity:get_uri()]
         if not valid_entity and widget_comp_uri then
            valid_entity = _is_widget_finished(r.entity:get_component(widget_comp_uri))
         end

         if valid_entity then
            log:spam('_calculate_stab_point %s: entity %s is valid', r.brick + r.normal, r.entity)
            -- ACE: if snap to grid enabled, snap the result to that x/z grid
            local brick = r.brick + r.normal
            self._raw_pos = brick
            if is_ctrl_held() then
               brick = self:_get_snap_grid_position(brick)
            end
            self._ignore_sink_offset = r.entity:get_id() ~= radiant._root_entity_id

            return brick, r.entity, r.normal
         end
      end
   end

   return nil, nil, nil
end

function AceTemplatePlacementTool:_get_snap_grid_position(pos)
   if not self._grid_offset then
      self._grid_offset = stonehearth.building:get_build_grid_offset()
   end

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
   log:spam('from bounds size %s rotated %s shifted by %s to %s', size, self._rotation, delta_fixup, center_shift)

   -- round to nearest grid dimensions
   local dest = pos - center_shift
   dest.x = math.floor(dest.x / grid + 0.5) * grid + self._grid_offset.x
   dest.z = math.floor(dest.z / grid + 0.5) * grid + self._grid_offset.y

   log:spam('converting %s to grid point %s', pos, dest + center_shift)

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
         log:spam('_test_template_placement: checking overlap %s', overlap)
         if radiant.entities.is_solid_entity(overlap) or
               (designation and not designation.allow_templates) or
               radiant.entities.get_entity_data(overlap, 'stonehearth:build2:blueprint') then
            found = false
            log:spam('_test_template_placement: overlap %s is not valid', overlap)
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

   log:spam('_place_template adjusting position from %s to %s', self._pos, brick)
   self._pos = brick

   self._render_entity:set_position(self:_get_sunk_position())
   self._render_entity:set_rotation(Point3(0, 360 - self._rotation, 0))
end

function AceTemplatePlacementTool:_get_sunk_position()
   return self._pos + (self._ignore_sink_offset and Point3.zero or self._sink_offset)
end

return AceTemplatePlacementTool
