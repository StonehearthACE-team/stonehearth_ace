local XZRegionSelector = require 'stonehearth.services.client.selection.xz_region_selector'
local selector_util = require 'stonehearth.services.client.selection.selector_util'
local RulerWidget = require 'stonehearth.services.client.selection.ruler_widget'
local pattern_lib = require 'stonehearth_ace.lib.pattern.pattern_lib'

local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Point2 = _radiant.csg.Point2
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3
local bindings = _radiant.client.get_binding_system()
local Entity = _radiant.om.Entity
local RegionCollisionType = _radiant.om.RegionCollisionShape

local PatternXZRegionSelector = class()
radiant.mixin(PatternXZRegionSelector, XZRegionSelector)

local OFFSCREEN = Point3(0, -100000, 0)
local INVALID_CURSOR = 'stonehearth:cursors:invalid_hover'
local REMOVE_CURSOR = 'stonehearth:cursors:clear'

local DEFAULT_BOX_COLOR = Color4(192, 192, 192, 255)

local INTERSECTION_NODE_NAME = 'pattern xz region selector intersection node'
local MAX_RESONABLE_DRAG_DISTANCE = 512
local MODEL_OFFSET = Point3(-0.5, 0, -0.5)

local log = radiant.log.create_logger('pattern_xz_region_selector')

function PatternXZRegionSelector:__init(reason)
   self._reason = tostring(reason)
   self._state = 'start'
   self._ruler_color_valid = Color4(255, 255, 255, 128)
   self._ruler_color_invalid = Color4(255, 0, 0, 128)
   self._require_supported = false
   self._require_unblocked = false
   self._show_rulers = true
   self._color = Color4(55, 187, 56, 255)
   self._rotation = 0
   self._rotate_entities = false
   self._auto_rotate = false
   self._min_size = 0
   self._max_size = radiant.math.MAX_INT32
   self._border = 0
   self._ignore_children = true
   self._select_front_brick = true
   self._validation_offset = Point3(0, 0, 0)
   self._model_offset = MODEL_OFFSET
   self._allow_select_cursor = false
   self._allow_unselectable_support_entities = false
   self._ignore_middle_collision = false
   self._invalid_cursor = INVALID_CURSOR
   self._remove_cursor = REMOVE_CURSOR
   self._valid_region_cache = Region3()
   self._pattern = {}
   self._pattern_entities = {}
   self._grid = {}
   self._grid_entities = {}

   self._on_keyboad_event_fn = function(e)
      if not self._auto_rotate then
         if bindings:is_action_active('build:rotate:left') then
            self._rotation = (self._rotation + 1) % 4
            self:set_requires_recalculation(true)
            return true
         elseif bindings:is_action_active('build:rotate:right') then
            self._rotation = (self._rotation + 3) % 4
            self:set_requires_recalculation(true)
            return true
         end
      end
   end
   self._on_mouse_event_fn = nil

   self._find_support_filter_fn = stonehearth.selection.find_supported_xz_region_filter

   local identity_end_point_transform = function(q0, q1)
      if not q0 or not q1 then
         return nil, nil
      end
      return Point3(q0), Point3(q1)   -- return a copy to be safe
   end

   local get_valid_axis_value = function(valid_vals, val)
      local lower, higher
      for _, valid in ipairs(valid_vals) do
         if val == valid then
            return val
         elseif val > valid then
            lower = valid
         elseif not lower then
            return valid
         else
            -- find the closer to val between lower and valid
            if val - lower <= valid - val then
               return lower
            else
               return valid
            end
         end
      end

      -- if they were all lower, cap the value at the highest lower value
      return lower or val
   end

   self._get_proposed_points_fn = identity_end_point_transform
   self._get_resolved_points_fn = function(p0, p1)
      local valid_x, valid_y = self._valid_x, self._valid_y
      if valid_x or valid_y then
         -- if size specifies only specific valid x/y dimensions, limit to those
         if not p0 or not p1 then
            return nil, nil
         end

         -- if we haven't selected the second point yet, just return the original (identical) points
         if not self:is_state('p0_selected') then
            return Point3(p0), Point3(p1)
         end
         
         -- get current size; have to consider rotation
         local length = p1 - p0
         local sign_x = length.x < 0 and -1 or 1
         local sign_z = length.z < 0 and -1 or 1
         local x = math.abs(length.x) + 1
         local y = math.abs(length.z) + 1

         if self._auto_rotate and (valid_x or valid_y) then
            -- adjust rotation (between 0 and 1) as necessary to best fit the primary length direction
            -- only matters if at least one length is being limited
            -- try to minimize the total difference between input points and resolved points
            -- don't change rotation if they're equal
            local x1, x2 = valid_x and get_valid_axis_value(valid_x, x) or x, valid_y and get_valid_axis_value(valid_y, x) or x
            local y1, y2 = valid_x and get_valid_axis_value(valid_x, y) or y, valid_y and get_valid_axis_value(valid_y, y) or y

            -- if x1/y2 is closest to x/y, use rotation 0 or 2
            -- if x2/y1 is closest to x/y, use rotation 1 or 3
            -- otherwise, stick with current rotation
            local check1 = math.abs(x1 - x) + math.abs(y2 - y)
            local check2 = math.abs(x2 - x) + math.abs(y1 - y)
            if check1 > check2 then
               self._rotation = sign_x > 0 and 1 or 3
               x, y = x2, y1
            else
               if check2 > check1 then
                  self._rotation = sign_z > 0 and 2 or 0
               else
                  -- if the checks were equal, look at the sign of the shortest dimension (pre-adjustment)
                  -- (we align with dragging back to front, and the long length is either right or left)
                  if y > x then
                     self._rotation = sign_x > 0 and 1 or 3
                  else
                     self._rotation = sign_z > 0 and 2 or 0
                  end
               end
               x, y = x1, y2
            end
         else
            if self._rotation == 1 or self._rotation == 3 then
               x, y = y, x
            end
   
            -- check each axis to see if the dimension is valid
            -- if it's not valid, get the closest valid value
            if valid_x then
               x = get_valid_axis_value(valid_x, x)
            end
            if valid_y then
               y = get_valid_axis_value(valid_y, y)
            end
   
            -- then we have to switch it back to the rotation/direction
            if self._rotation == 1 or self._rotation == 3 then
               x, y = y, x
            end
         end

         local q0, q1 = Point3(p0), Point3(p1)
         q1.x = q0.x + sign_x * (x - 1)
         q1.z = q0.z + sign_z * (y - 1)

         return q0, q1
      else
         return identity_end_point_transform(p0, p1)
      end
   end

   self._cursor_fn = function(selected_cube, stabbed_normal)
      if not selected_cube then
         return self._invalid_cursor
      end
      return self._cursor
   end

   self._last_ignored_entities = {}
   self._ignored_entities = {}

   self:_initialize_dispatch_table()

   local prev_box, prev_rotation
   self:use_manual_marquee(function(xz_region_selector, box, start_location, stabbed_normal)
      -- this first section is the default marquee that we also want to render
      -- save these to be sent to the presence service to render on other players' clients
      local region_shape = box
      local region_type = 'Region2'
      -- recreate the render node for the designation
      local size = box:get_size()
      local region = Region2(Rect2(Point2.zero, Point2(size.x, size.z)))
      local render_node = _radiant.client.create_designation_node(RenderRootNode, region, self._color, self._color):set_position(box.min)

      -- now add/remove crop entities based on size
      -- only adjust them if the selection box has actually changed size
      if self:is_state('p0_selected') and (not prev_box or prev_box.min ~= box.min or prev_box.max ~= box.max or prev_rotation ~= self._rotation) then
         prev_box = box
         prev_rotation = self._rotation
         self:_render_grid_entity_nodes(box)
      end

      return render_node, region_shape, region_type
   end)
end

function PatternXZRegionSelector:set_valid_dims(valid_x, valid_y)
   self._valid_x = valid_x
   self._valid_y = valid_y
   self._max_x = valid_x and valid_x[#valid_x]
   self._max_y = valid_y and valid_y[#valid_y]
   return self
end

function PatternXZRegionSelector:set_border(border)
   self._border = border
   return self
end

function PatternXZRegionSelector:set_color(color)
   self._color = color
   return self
end

function PatternXZRegionSelector:set_pattern(pattern, pattern_entities)
   self._pattern = pattern
   self._pattern_entities = pattern_entities
   return self
end

function PatternXZRegionSelector:set_auto_rotate(auto_rotate)
   self._auto_rotate = auto_rotate
   return self
end

function PatternXZRegionSelector:set_rotation(rotation)
   self._rotation = rotation
   return self
end

function PatternXZRegionSelector:set_rotate_entities(rotate_entities)
   self._rotate_entities = rotate_entities
   return self
end

function PatternXZRegionSelector:set_model_offset(offset)
   self._model_offset = offset
   return self
end

function PatternXZRegionSelector:_on_restart(...)
   self:_hide_grid_entity_nodes()
   if self._restart_cb then
      self:_restart_cb(...)
   end
end

function PatternXZRegionSelector:_get_pattern_entity(x, y, max_size)
   if x < 1 or y < 1 or x > max_size or y > max_size then
      return false
   end

   local location_type = pattern_lib.get_location_type(self._pattern, x, y)
   local data = self._pattern_entities[location_type]
   if data and data.uri then
      local entity = radiant.entities.create_entity(data.uri)
      entity:add_component('region_collision_shape'):set_region_collision_type(_radiant.om.RegionCollisionShape.NONE)
      if data.model_variant then
         entity:get_component('render_info'):set_model_variant(data.model_variant)
      end
      return entity
   end

   return false
end

function PatternXZRegionSelector:get_rotation()
   return self._rotation
end

function PatternXZRegionSelector:get_grid_entity_locations()
   if self._pattern_calculator then
      return self._pattern_calculator:get_locations_by_type()
   end

   return {}
end

function PatternXZRegionSelector:_initialize_grid()
   self:_destroy_grid_entities()

   local grid = {}
   local grid_entities = {}

   local border = self._border
   local max_size_interior = self._max_size - border * 2

   for x = 1, max_size_interior do
      local row = {}
      for y = 1, max_size_interior do
         local entity = self:_get_pattern_entity(x, y, max_size_interior)
         row[y] = entity
         if entity then
            grid_entities[entity] = false
         end
      end
      grid[x] = row
   end

   self._grid = grid
   self._grid_entities = grid_entities
end

function PatternXZRegionSelector:_destroy_grid_entities()
   for entity, render_trace in pairs(self._grid_entities) do
      if render_trace then
         render_trace:destroy()
      end
      radiant.entities.destroy_entity(entity)
   end
   self._grid_entities = {}
   self._grid = {}
end

function PatternXZRegionSelector:_hide_grid_entity_nodes()
   for grid_entity, _ in pairs(self._grid_entities) do
      local render_entity = _radiant.client.get_render_entity(grid_entity)
      if render_entity and render_entity:is_valid() then
         render_entity:get_node():set_visible(false)
      end
   end
end

function PatternXZRegionSelector:_render_grid_entity_nodes(box)
   local size = box:get_size()
   local border = self._border
   local max_size = self._max_size
   local xb_max, yb_max = size.x - border * 2, size.z - border * 2
   local color = self._color
   self._pattern_calculator = PatternCalculator(self._pattern, self._max_size, self._border)
      :set_rotation(self._rotation):set_size(size.x, size.z)

   self:_hide_grid_entity_nodes()

   for x = 1, max_size do
      for y = 1, max_size do
         local rot_x, rot_y = self._pattern_calculator:get_pattern_coords(x, y)
         if rot_x and rot_y then
            local entity = self._grid[rot_x][rot_y]
            if entity then
               local location = box.min + Point3(x - 1, 0, y - 1)
               if location.x < box.max.x and location.z < box.max.z then
                  radiant.terrain.place_entity_at_exact_location(entity, location, {force_iconic = false})
                  if self._rotate_entities then
                     radiant.entities.turn_to(entity, -self._rotation * 90)
                  end
                  if not self._grid_entities[entity] then
                     self._grid_entities[entity] = _radiant.client.trace_render_frame()
                        :on_frame_start('adjust grid entity', function(now, alpha, frame_time, frame_time_wallclock)
                              local render_entity = _radiant.client.get_render_entity(entity)
                              if render_entity and render_entity:is_valid() then
                                 render_entity:add_query_flag(_radiant.renderer.QueryFlags.UNSELECTABLE)
                                 render_entity:get_node():set_can_query(false)
                                 render_entity:get_node():set_visible(true)
                                 render_entity:get_model():set_material('materials/always_on_top_obj.material.json', true)
                                 render_entity:get_model():get_material():set_vector_parameter('widgetColor', color.r / 255.0, color.g / 255.0, color.b / 255.0, 0.4)
                                 self._grid_entities[entity]:destroy()
                                 self._grid_entities[entity] = false
                              end
                           end)
                  end
               end
            end
         end
      end
   end
end

function PatternXZRegionSelector:_cleanup()
   log:spam('cleaning up: %s', self._reason)
   stonehearth.selection:register_tool(self, false)
   stonehearth.presence_client:update_xz_selection(nil)

   self:_destroy_grid_entities()
   self:_restore_ignored_entities()

   self._fail_cb = nil
   self._progress_cb = nil
   self._done_cb = nil
   self._always_cb = nil

   if self._input_capture then
      self._input_capture:destroy()
      self._input_capture = nil
   end

   if self._cursor_obj then
      self._cursor_obj:destroy()
      self._cursor_obj = nil
   end

   if self._render_node then
      self._render_node:destroy()
      self._render_node = nil
   end

   if self._x_ruler then
      self._x_ruler:destroy()
      self._x_ruler = nil
   end

   if self._z_ruler then
      self._z_ruler:destroy()
      self._z_ruler = nil
   end

   if self._intersection_node then
      self._intersection_node:destroy()
      self._intersection_node = nil
   end
end

function PatternXZRegionSelector:go()
   self:_initialize_grid()

   -- install a new mouse cursor if requested by the client.  this cursor
   -- will stick around until :destroy() is called on the selector!
   if self._cursor then
      self._cursor_obj = _radiant.client.set_cursor(self._cursor)
   end

   stonehearth.selection:register_tool(self, true)

   if self._show_rulers then
      self._x_ruler = RulerWidget()
      self._z_ruler = RulerWidget()
   end

   assert(not self._input_capture, 'attempting to go twice')

   self._input_capture = stonehearth.input:capture_input('PatternXZRegionSelector '..self._reason)
                           :on_mouse_event(function(e)
                                 if self._on_mouse_event_fn then
                                    if self._on_mouse_event_fn(e) then
                                       self._action = 'notify'
                                       self:_update()
                                       return true
                                    end
                                 end
                                 return self:_on_mouse_event(e)
                              end)
                           :on_keyboard_event(function(e)
                                 if self._on_keyboad_event_fn then
                                    if self._on_keyboad_event_fn(e) then
                                       self._action = 'notify'
                                       self:_update()
                                       return true
                                    end
                                 end
                                 return false
                              end)

   -- TODO: want to be able to call this
   -- self._input_capture:push_object_state()

   -- Report that the xz_region_selector is setup, this is for the auto tests.
   radiant.events.trigger(radiant, 'radiant:pattern_xz_region_selector:go', self._reason, self)

   return self
end

return PatternXZRegionSelector
