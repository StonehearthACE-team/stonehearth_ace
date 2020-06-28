--[[
   Developed primarily for extending water pump pipes, but designed to be generic.
   Since the destination can be somewhere in the air, we can't just use the regular entity_or_location_selector.
   Mouse handling may be difficult, so for now just specify keys: rotate-cw, rotate-ccw, increase, and decrease.
]]

local SelectorBase = require 'stonehearth.services.client.selection.selector_base'
local selector_util = require 'stonehearth.services.client.selection.selector_util'
local Point3 = _radiant.csg.Point3
local bindings = _radiant.client.get_binding_system()
local Entity = _radiant.om.Entity
local XYZRangeSelector = class()
local FootprintWidget = require 'services.client.selection.footprint_widget'

radiant.mixin(XYZRangeSelector, SelectorBase)

local OFFSCREEN = Point3(0, -100000, 0)
local INVALID_CURSOR = 'stonehearth:cursors:invalid_hover'

function XYZRangeSelector:resolve(...)
   XYZRangeSelector._last_facing = self._rotation
   self:_call_once('done', ...)
   self:_call_once('always')
   self:_cleanup()
   return self
end

function XYZRangeSelector:_shift_down()
  return _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_LEFT_SHIFT) or
         _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_RIGHT_SHIFT)
end

-- "rotations" are considered relative to this entity (in terms of its position and rotation)
function XYZRangeSelector:set_relative_entity(entity)
   self._relative_entity = entity
end

-- this is a list of the axes (relative to the entity's rotation) along which the range can be specified
-- it includes their origin point (relative to the entity) and a directional vector point, along with min/max length
-- which override the base min/max length
-- { origin = Point3, dimension = string, direction = Point3, min_length = number, max_length = number }
function XYZRangeSelector:set_rotations(rotations)
   self._rotations = rotations
   self._region_needs_refresh = true
   return self
end

function XYZRangeSelector:get_rotation()
   return self._rotations[self._rotation + 1]
end

function XYZRangeSelector:set_rotation(rotation)
   -- this rotation behaves differently than normal rotations; this is just an index of the _rotations array
   if self._rotation ~= rotation then
      self._rotation = rotation
      self._region_needs_refresh = true
   end
   return self
end

function XYZRangeSelector:set_length(length)
   if self._length ~= length then
      self._length = length
      self._region_needs_refresh = true
   end
   return self
end

function XYZRangeSelector:_get_length()
   local rotation = self:get_rotation()
   return math.max(rotation.min_length, math.min(rotation.max_length, self._length or rotation.max_length))
end

function XYZRangeSelector:set_render_params(material, color, custom_fn)
   self._render_material = material or (not custom_fn and '/stonehearth/data/horde/materials/transparent_box_nodepth.material.json')
   self._render_color = color or (not custom_fn and Color4(80, 192, 0, 255))
   self._render_custom_fn = custom_fn
end

-- handles keyboard events from the input service
function XYZRangeSelector:_on_keyboard_event(e)
   local event_consumed = false
   local deltaRot = 0
   local deltaExt = 0

   local num_rotations = #self._rotations

   if num_rotations > 1 then
      if bindings:is_action_active('stonehearth_ace:range_selection:rotate:left') then
         deltaRot = 1
      elseif bindings:is_action_active('stonehearth_ace:range_selection:rotate:right') then
         deltaRot = num_rotations - 1
      elseif bindings:is_action_active('stonehearth_ace:range_selection:lengthen') then
         deltaExt = 1
      elseif bindings:is_action_active('stonehearth_ace:range_selection:shorten') then
         deltaExt = num_rotations - 1
      end

      if deltaRot ~= 0 then
         local new_rotation = ((self._rotation - 1 + deltaRot) % num_rotations) + 1
         self:set_rotation(new_rotation)
         event_consumed = true
      end

      if deltaExt ~= 0 then
         self:set_length(self._length + deltaExt)
         event_consumed = true
      end
   end

   return event_consumed
end

function XYZRangeSelector:_update_rulers(p0, p1, is_region)
   if not self._show_rulers or not self._x_ruler or not self._y_ruler or not self._z_ruler then
      return
   end

   if p0 and p1 then
      -- if we're selecting the hover brick, the rulers are on the bottom of the selection
      -- if we're selecting the terrain brick, the rulers are on the top of the selection
      local offset = (self._select_front_brick or is_region) and Point3.zero or Point3.unit_y
      local q0, q1 = p0 + offset, p1 + offset

      local rotation = self:get_rotation()
      if rotation then
         self:_update_ruler(self['_' .. rotation.dimension .. '_ruler'], q0, q1, rotation.dimension, is_region)
      end
   else
      self._x_ruler:hide()
      self._y_ruler:hide()
      self._z_ruler:hide()
   end
end

--[[


]]

local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local selector_util = require 'stonehearth.services.client.selection.selector_util'
local RulerWidget = require 'stonehearth.services.client.selection.ruler_widget'
local XZRegionSelector = require 'stonehearth.services.client.selection.xz_region_selector'
local XYZRangeSelector = class()
local Color4 = _radiant.csg.Color4
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Point2 = _radiant.csg.Point2
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3

radiant.mixin(XYZRangeSelector, XZRegionSelector)

local log = radiant.log.create_logger('xyz_range_selector')

local DEFAULT_BOX_COLOR = Color4(192, 192, 192, 255)

local INTERSECTION_NODE_NAME = 'xyz range selector intersection node'
local MAX_RESONABLE_DRAG_DISTANCE = 512
local MODEL_OFFSET = Point3(-0.5, 0, -0.5)
local TERRAIN_NODES = 1

function XYZRangeSelector:__init(reason)
   self._reason = tostring(reason)
   self._state = 'start'
   self._ruler_color_valid = Color4(255, 255, 255, 128)
   self._ruler_color_invalid = Color4(255, 0, 0, 128)
   self._require_supported = false
   self._require_unblocked = false
   self._show_rulers = true
   self._min_size = 0
   self._max_size = radiant.math.MAX_INT32
   self._select_front_brick = true
   self._validation_offset = Point3(0, 0, 0)
   self._allow_select_cursor = false
   self._allow_unselectable_support_entities = false
   self._invalid_cursor = 'stonehearth:cursors:invalid_hover'
   self._valid_region_cache = Region3()
   self._on_keyboad_event_fn = nil
   self._on_mouse_event_fn = nil

   self._find_support_filter_fn = stonehearth.selection.find_supported_xz_region_filter

   local identity_end_point_transform = function(q0, q1)
      if not q0 or not q1 then
         return nil, nil
      end
      return Point3(q0), Point3(q1)   -- return a copy to be safe
   end

   self._get_proposed_points_fn = identity_end_point_transform
   self._get_resolved_points_fn = identity_end_point_transform

   self._cursor_fn = function(selected_cube, stabbed_normal)
      if not selected_cube then
         return self._invalid_cursor
      end
      return self._cursor
   end

   self._last_ignored_entities = {}
   self._ignored_entities = {}

   self:_initialize_dispatch_table()

   self:use_outline_marquee(DEFAULT_BOX_COLOR, DEFAULT_BOX_COLOR)
end

function XYZRangeSelector:set_min_size(value)
   self._min_size = value
   return self
end

function XYZRangeSelector:set_max_size(value)
   self._max_size = value
   return self
end

function XYZRangeSelector:set_show_rulers(value)
   self._show_rulers = value
   return self
end

function XYZRangeSelector:select_front_brick(value)
   self._select_front_brick = value
   return self
end

-- ugly parameter used to validate a different region than the selected region
function XYZRangeSelector:set_validation_offset(value)
   self._validation_offset = value
   return self
end

function XYZRangeSelector:require_supported(supported)
   self._require_supported = supported
   return self
end

function XYZRangeSelector:require_unblocked(unblocked)
   self._require_unblocked = unblocked
   return self
end

function XYZRangeSelector:set_keyboard_event_handler(keyboard_event_handler)
   self._on_keyboad_event_fn = keyboard_event_handler
   return self
end

function XYZRangeSelector:set_mouse_event_handler(mouse_event_handler)
   self._on_mouse_event_fn = mouse_event_handler
   return self
end

function XYZRangeSelector:set_find_support_filter(filter_fn)
   self._find_support_filter_fn = filter_fn
   return self
end

-- set the 'can_contain_entity_filter'.  when growing the xz region,
-- make sure that it does *not* contain any of the entities for which
-- this filter returns false
function XYZRangeSelector:set_can_contain_entity_filter(filter_fn)
   self._can_contain_entity_filter_fn = filter_fn
   return self
end

function XYZRangeSelector:set_ghost_ignored_entity_filter(filter_fn)
   self._ghost_ignored_entity_filter_fn = filter_fn
   return self
end

-- used to constrain the selected region
-- examples include forcing the region to be square, enforcing minimum or maximum sizes,
-- or quantizing the region to certain step sizes
function XYZRangeSelector:set_end_point_transforms(get_proposed_points_fn, get_resolved_points_fn)
   self._get_proposed_points_fn = get_proposed_points_fn
   self._get_resolved_points_fn = get_resolved_points_fn
   return self
end

function XYZRangeSelector:allow_select_cursor(allow)
   self._allow_select_cursor = allow
   return self
end

function XYZRangeSelector:set_cursor(cursor)
   self._cursor = cursor
   return self
end

function XYZRangeSelector:set_invalid_cursor(invalid_cursor)
   self._invalid_cursor = invalid_cursor
   return self
end

function XYZRangeSelector:set_cursor_fn(cursor_fn)
   self._cursor_fn = cursor_fn
   return self
end

function XYZRangeSelector:use_designation_marquee(color)
   self._create_node_fn = _radiant.client.create_designation_node
   self._box_color = color
   self._line_color = color
   return self
end

function XYZRangeSelector:use_outline_marquee(box_color, line_color)
   self._create_node_fn = _radiant.client.create_selection_node
   self._box_color = box_color
   self._line_color = line_color
   return self
end

function XYZRangeSelector:use_manual_marquee(marquee_fn)
   self._create_marquee_fn = marquee_fn
   return self
end

function XYZRangeSelector:done(cb)
   self._done_cb = cb
   return self
end

function XYZRangeSelector:progress(cb)
   self._progress_cb = cb
   return self
end

function XYZRangeSelector:fail(cb)
   self._fail_cb = cb
   return self
end

function XYZRangeSelector:always(cb)
   self._always_cb = cb
   return self
end

function XYZRangeSelector:_call_once(name, ...)
   local method_name = '_' .. name .. '_cb'
   if self[method_name] then
      local method = self[method_name]
      self[method_name] = nil
      method(self, ...)
   end
end

function XYZRangeSelector:resolve(...)
   self:_call_once('done', ...)
   self:_call_once('always')
   -- If we've resolved, we can't possibly fail.
   self._fail_cb = nil
   self:_cleanup()
   return self
end

function XYZRangeSelector:reject(...)
   self:_call_once('fail', ...)
   self:_call_once('always')
   -- If we've rejected, we can't possibly succeed.
   self._done_cb = nil
   self:_cleanup()
   return self
end

function XYZRangeSelector:notify(...)
   if self._progress_cb then
      self._progress_cb(self, ...)
   end
   return self
end

function XYZRangeSelector:_cleanup()
   log:spam('cleaning up: %s', self._reason)
   stonehearth.selection:register_tool(self, false)
   stonehearth.presence_client:update_xz_selection(nil)

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

   if self._y_ruler then
      self._y_ruler:destroy()
      self._y_ruler = nil
   end

   if self._z_ruler then
      self._z_ruler:destroy()
      self._z_ruler = nil
   end

   if self._intersection_nodes then
      for _, node in ipairs(self._intersection_nodes) do
         node.node:destroy()
      end
      self._intersection_nodes = nil
   end
end

function XYZRangeSelector:destroy()
   self:reject('destroy')
end

-- return whether or not the given location is valid to be used in the creation
-- of the xz region.
function XYZRangeSelector:_is_valid_location(brick)
   if not brick then
      return false
   end

   if self._require_unblocked and radiant.terrain.is_blocked(brick) then
      return false
   end
   if self._require_supported and not radiant.terrain.is_supported(brick) then
      return false
   end
   if self._can_contain_entity_filter_fn then
      local entities = radiant.terrain.get_entities_at_point(brick)
      for _, entity in pairs(entities) do
         if not self._can_contain_entity_filter_fn(entity, self) then
            return false
         end
      end
   end
   return true
end

-- get the brick under the screen coordinate (x, y) which is the best candidate
-- for adding to the xz region selector.  if `check_containment_filter` is true, will
-- also make sure that all the entities at the specified poit pass the can_contain_entity_filter
-- filter.
function XYZRangeSelector:_get_brick_at(x, y)
   local brick, normal = selector_util.get_selected_brick(x, y, function(result)
         local entity = result.entity

         for _, node in ipairs(self._intersection_nodes) do
            if result.node_name == node.node_name then
               -- we hit an intersection node created by the user to catch points floating
               -- in air.  use this brick
               return true
            end
         end

         return false
      end)
   return brick, normal
end

-- Given a candidate p1, compute the 'best' p1 which results in a valid xz region.
-- The basic algorithm is simple:
--     1) For each row, scan until you reach an invalid point or the x limit of a previous row.
--     2) Add each valid point to a region.
--     3) Return the point in the region closest to p1.
-- The rest of the code is just optimization and bookkeeping.
function XYZRangeSelector:_compute_endpoint(q0, q1)
   if not q0 or not q1 then
      return nil
   end

   -- if q0 has changed, invalidate our cache
   if q0 ~= self._valid_region_origin then
      self._valid_region_cache:clear()
      self._valid_region_origin = Point3(q0)
   end

   -- if the endpoints are already validated, then the whole cube is valid
   if self._valid_region_cache:contains(q0) and self._valid_region_cache:contains(q1) then
      return q1
   end

   if not self:_is_valid_location(q0) then
      return nil
   end

   local dx = q1.x > q0.x and 1 or -1
   local dz = q1.z > q0.z and 1 or -1
   local r0 = Point3(q0) -- row start point
   local r1 = Point3(q0) -- row end point
   local limit_x = q1.x
   local valid_x, start_x

   -- iterate over all rows
   for j = q0.z, q1.z, dz do
      if not limit_x then
         -- row is completely obstructed, no further rows can be valid
         break
      end

      r0.z = j
      r1.z = j

      r1.x = limit_x
      local unverified_region = Region3(csg_lib.create_cube(r0, r1))
      unverified_region:subtract_region(self._valid_region_cache)

      if not unverified_region:empty() then
         local valid_x = nil
         local start_x = unverified_region:get_closest_point(q0).x

         -- if we're not at the row start, valid_x was the previous point
         if start_x ~= r0.x then
            valid_x = start_x - dx
         end

         -- iterate over the untested columns in the row
         for i = start_x, limit_x, dx do
            r1.x = i
            if self:_is_valid_location(r1) then
               valid_x = i
            else
               -- the new limit is the last valid x value
               limit_x = valid_x
               break
            end
         end

         if valid_x then
            -- add the row to the valid_region
            r1.x = valid_x
            local valid_row = csg_lib.create_cube(r0, r1)
            self._valid_region_cache:add_cube(valid_row)
         end
      end
   end

   self._valid_region_cache:optimize('xzregionselector:_compute_endpoint')
   local resolved_q1 = self._valid_region_cache:get_closest_point(q1)
   return resolved_q1
end

function XYZRangeSelector:_find_valid_region(q0, q1)
   if not q0 or not q1 then
      return nil, nil
   end

   -- validation offset is an annoying hack used to validate regions that are offset from the selected region
   -- used for things like mining zones, roads, and floors
   local offset = self._validation_offset
   local v0, v1 = q0 + offset, q1 + offset

   v1 = self:_compute_endpoint(v0, v1)
   if not v1 then
      return nil, nil
   end

   q1 = v1 - offset

   return q0, q1
end

function XYZRangeSelector:_update()
   if not self._action then
      return
   end

   if self._action == 'reject' then
      self:reject({ error = 'selection cancelled' }) -- is this still the correct argument?
      return
   end

   local selected_cube = self._p0 and self._p1 and csg_lib.create_cube(self._p0, self._p1)

   self:_update_selected_cube(selected_cube)
   if self._region_type == 'Region3' and self._region_shape then
      local bounds = self._region_shape:get_bounds()
      self:_update_rulers(bounds.min, bounds.max, true)
   else
      self:_update_rulers(self._p0, self._p1, false)
   end
   self:_update_cursor(selected_cube, self._stabbed_normal)
   self:_update_ignored_entities()

   if self._action == 'notify' then
      self:notify(selected_cube, self._p0)
   elseif self._action == 'resolve' then
      self:resolve(selected_cube, self._p0, self._stabbed_normal)
   else
      log:error('uknown action: %s', self._action)
      assert(false)
   end

   if self._region_shape then
      stonehearth.presence_client:update_xz_selection(self._action, self._region_shape, self._region_type, self._reason)
   end
end

function XYZRangeSelector:_resolve_endpoints(q0, q1, stabbed_normal)
   log:spam('selected endpoints: %s, %s', tostring(q0), tostring(q1))

   q0, q1 = self._get_proposed_points_fn(q0, q1, stabbed_normal)
   log:spam('proposed endpoints: %s, %s', tostring(q0), tostring(q1))

   q0, q1 = self:_find_valid_region(q0, q1)
   log:spam('validated endpoints: %s, %s', tostring(q0), tostring(q1))

   q0, q1 = self:_limit_dimensions(q0, q1)
   log:spam('bounded endpoints: %s, %s', tostring(q0), tostring(q1))

   q0, q1 = self._get_resolved_points_fn(q0, q1, stabbed_normal)
   log:spam('resolved endpoints: %s, %s', tostring(q0), tostring(q1))

   if not q0 or not q1 then
      return nil, nil
   end

   return q0, q1
end

function XYZRangeSelector:_limit_dimensions(q0, q1)
   if not q0 or not q1 then
      return nil, nil
   end

   local new_q1 = Point3(q1)
   local size = csg_lib.create_cube(q0, q1):get_size()

   if size.x > self._max_size then
      local sign = q1.x >= q0.x and 1 or -1
      new_q1.x = q0.x + sign*(self._max_size-1)
   end

   if size.z > self._max_size then
      local sign = q1.z >= q0.z and 1 or -1
      new_q1.z = q0.z + sign*(self._max_size-1)
   end

   return q0, new_q1
end

function XYZRangeSelector:_on_mouse_event(event)
   if not event then
      return false
   end

   local event_consumed
   if stonehearth.selection.user_cancelled(event) then
      self._action = 'reject'
      event_consumed = true
   elseif event:up(1) then
      self._action = 'resolve'
      event_consumed = true
   else
      self._action = 'notify'

      local brick, normal = self:_get_brick_at(event.x, event.y)

      if brick and brick ~= self._last_brick then
         self._last_brick = brick

         -- search intersection nodes for which rotation this could be
         local rotation_index
         for i, node in ipairs(self._intersection_nodes) do
            if node.cube:contains(brick) then
               rotation_index = i
               break
            end
         end

         if rotation_index then
            self._rotation = rotation_index
            local rotation = self:get_rotation()
            local node = self._intersection_nodes[rotation_index]
            local cube = csg_lib.create_cube(brick, node.min_point)
            self:set_length(cube:get_size()[rotation.dimension])
         end
      end
   end

   self:_update()

   return event_consumed
end

function XYZRangeSelector:_is_valid_length(length)
   local valid = length >= self._min_size and length <= self._max_size
   return valid
end

function XYZRangeSelector:_are_valid_dimensions(p0, p1)
   local size = csg_lib.create_cube(p0, p1):get_size()
   local valid = self:_is_valid_length(size.x) and self:_is_valid_length(size.z)
   return valid
end

function XYZRangeSelector:_update_rulers(p0, p1, is_region)
   if not self._show_rulers or not self._x_ruler or not self._y_ruler or not self._z_ruler then
      return
   end

   if p0 and p1 then
      -- if we're selecting the hover brick, the rulers are on the bottom of the selection
      -- if we're selecting the terrain brick, the rulers are on the top of the selection
      local offset = (self._select_front_brick or is_region) and Point3.zero or Point3.unit_y
      local q0, q1 = p0 + offset, p1 + offset

      local rotation = self:get_rotation()
      if rotation then
         self:_update_ruler(self['_' .. rotation.dimension .. '_ruler'], q0, q1, rotation.dimension, is_region)
      end
   else
      self._x_ruler:hide()
      self._y_ruler:hide()
      self._z_ruler:hide()
   end
end

function XYZRangeSelector:_update_ruler(ruler, p0, p1, dimension, is_region)
   local d = dimension
   local dn = d == 'x' and 'z' or 'x'
   local min = math.min(p0[d], p1[d])
   local max = math.max(p0[d], p1[d])
   local length = math.floor(max - min + (is_region and 0 or 1) + 0.5)
   if length <= 1 then
      ruler:hide()
      return
   end

   local color = self:_is_valid_length(length) and self._ruler_color_valid or self._ruler_color_invalid
   ruler:set_color(color)

   local min_point = Point3(p1)
   min_point[d] = min

   local max_point = Point3(p1)
   max_point[d] = max

   if is_region then
      min_point[dn] = min_point[dn] - 1
      max_point = max_point - Point3(1, 0, 1)
   end

   -- don't use Point3.zero since we need it to be mutable
   local normal = Point3(0, 0, 0)
   normal[dn] = p0[dn] <= p1[dn] and 1 or -1

   ruler:set_points(min_point, max_point, normal, string.format('%d', length))
   ruler:show()
end

function XYZRangeSelector:_update_cursor(box, stabbed_normal)
   local cursor = self._cursor_fn and self._cursor_fn(box, stabbed_normal)

   if cursor == self._current_cursor then
      return
   end

   if self._cursor_obj then
      self._cursor_obj:destroy()
      self._cursor_obj = nil
   end

   if cursor then
      self._cursor_obj = _radiant.client.set_cursor(cursor)
   end
end

function XYZRangeSelector:_update_ignored_entities()
   if not self._ghost_ignored_entity_filter_fn then
      return
   end

   -- ghost entities that are new to the ignored_entities set
   self:_each_item_not_in_map(self._ignored_entities, self._last_ignored_entities, function(item)
         self:_set_ghost_mode(item.entity)
      end)

   -- unghost entities that have left the ignored_entities set
   self:_each_item_not_in_map(self._last_ignored_entities, self._ignored_entities, function(item)
         self:_set_entity_material(item.entity, item.material)
      end)

   self._last_ignored_entities = self._ignored_entities
   self._ignored_entities = {}
end

-- calls fn for each item in map that is not in the reference_map
function XYZRangeSelector:_each_item_not_in_map(map, reference_map, fn)
   for id, item in pairs(map) do
      if not reference_map[id] then
         fn(item)
      end
   end
end

function XYZRangeSelector:_add_to_ignored_entities(entity)
   local id = entity:get_id()
   local value = self._last_ignored_entities[id]

   if not value then
      local render_entity = _radiant.client.get_render_entity(entity)
      local material = render_entity:get_material_override()
      value = {
         entity = entity,
         material = material
      }
   end

   self._ignored_entities[id] = value
end

function XYZRangeSelector:_restore_ignored_entities()
   for id, item in pairs(self._last_ignored_entities) do
      self:_set_entity_material(item.entity, item.material)
   end
end

function XYZRangeSelector:_set_ghost_mode(entity, ghost_mode)
   if not entity:is_valid() then
      return
   end

   local render_entity = _radiant.client.get_render_entity(entity)
   local material = render_entity:get_material_path('hud')
   if material and material ~= '' then
      render_entity:set_material_override(material)
   end
end

function XYZRangeSelector:_set_entity_material(entity, material)
   if not entity:is_valid() then
      return
   end

   local render_entity = _radiant.client.get_render_entity(entity)
   render_entity:set_material_override(material)
end

function XYZRangeSelector:_recalc_current_region()
   self._region_needs_refresh = false

   local rotation = self:get_rotation()
   local length = self:_get_length()
   local node = self._intersection_nodes[self._rotation]

   if length and rotation and node and length > 0 then
      local cube = csg_lib.create_cube(rotation.origin, rotation.origin + (length - 1) * rotation.direction)

      -- make sure there are no entities with collision in this cube (or check custom filter)
      local cube_is_good = true
      local entities = radiant.terrain.get_entities_in_cube(cube)
      for _, entity in pairs(entities) do
         if (self._can_contain_entity_filter_fn and not self._can_contain_entity_filter_fn(entity, self)) then
            cube_is_good = false
            break
         else
            local rcs = entity:get_component('region_collision_shape')
            local rc_type = rcs and rcs:get_region_collision_type()
            if rc_type == RegionCollisionType.SOLID or rc_type == RegionCollisionType.PLATFORM then
               cube_is_good = false
               break
            end
         end
      end

      if cube_is_good then
         self._current_region = Region3(cube)
      end
   else
      self._current_region = nil
   end

   self:_update_render()

   return self._current_region
end

function XYZRangeSelector:get_current_region()
   if not self._current_region or self._region_needs_refresh then
      self:_recalc_current_region()
   end

   return self._current_region
end

function XYZRangeSelector:_update_render()
   if self._render_node then
      self._render_node:destroy()
      self._render_node = nil
   end

   if self._render_material and self._render_color and self._current_region then
      self._render_node = _radiant.client.create_region_outline_node(RenderRootNode, self._current_region,
                           radiant.util.to_color4(self._render_color, 32),
                           radiant.util.to_color4(self._render_color, 192),
                           self._render_material, 1)
            :set_visible(true)
            :set_casts_shadows(false)
            :set_can_query(false)
   end

   if self._render_custom_fn then
      self._render_custom_fn(self)
   end
end

function XYZRangeSelector:go()
   -- install a new mouse cursor if requested by the client.  this cursor
   -- will stick around until :destroy() is called on the selector!
   if self._cursor then
      self._cursor_obj = _radiant.client.set_cursor(self._cursor)
   end

   stonehearth.selection:register_tool(self, true)

   if self._show_rulers then
      self._x_ruler = RulerWidget()
      self._y_ruler = RulerWidget()
      self._z_ruler = RulerWidget()
   end

   -- load up the rotations
   -- local facing = 0
   -- if self._relative_entity then
   --    facing = radiant.entities.get_facing(self._relative_entity)
   -- end

   local nodes = {}
   for i, rotation in ipairs(self._rotations) do
      -- { origin = Point3, dimension = string, direction = Point3, min_length = number, max_length = number }
      --local direction = direction:rotated(facing)
      local origin = rotation.origin
      local render_node = self._relative_entity and _radiant.client.get_render_entity(self._relative_entity):get_node() or RenderRootNode
      local min_point = origin + (rotation.min_length - 1) * rotation.direction
      local max_point = origin + (rotation.max_length - 1) * rotation.direction
      local cube = csg_lib.create_cube(min_point, max_point)
      local name = INTERSECTION_NODE_NAME .. i

      local node = _radiant.client.create_voxel_node(render_node, Region3(cube), '', MODEL_OFFSET)
                                                   :set_name(name)
                                                   :set_visible(false)
                                                   :set_can_query(true)

      table.insert(nodes, {
         min_point = min_point,
         cube = cube,
         name = name,
         node = node
      })
   end
   self._intersection_nodes = nodes

   assert(not self._input_capture, 'attempting to go twice')

   self._input_capture = stonehearth.input:capture_input('XYZRangeSelector '..self._reason)
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
   --radiant.events.trigger(radiant, 'radiant:xz_region_selector:go', self._reason, self)

   return self
end

return XYZRangeSelector
