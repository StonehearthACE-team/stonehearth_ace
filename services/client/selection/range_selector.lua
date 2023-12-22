--[[
   Developed primarily for extending water pump pipes, but designed to be generic.
   Since the destination can be somewhere in the air, we can't just use the regular entity_or_location_selector.
   Mouse handling may be difficult, so for now just specify keys: rotate-cw, rotate-ccw, increase, and decrease.
]]

local SelectorBase = require 'stonehearth.services.client.selection.selector_base'
local selector_util = require 'stonehearth.services.client.selection.selector_util'
local csg_lib = require 'stonehearth.lib.csg.csg_lib'
local util = require 'stonehearth_ace.lib.util'
local XYZRulerWidget = require 'stonehearth_ace.services.client.selection.xyz_ruler_widget'
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
local XYZRangeSelector = class()

radiant.mixin(XYZRangeSelector, SelectorBase)

local OFFSCREEN = Point3(0, -100000, 0)
local INVALID_CURSOR = 'stonehearth:cursors:invalid_hover'
local REMOVE_CURSOR = 'stonehearth:cursors:clear'
local log = radiant.log.create_logger('xyz_range_selector')

local DEFAULT_BOX_COLOR = Color4(80, 192, 0, 255)
local DEFAULT_CANCEL_BOX_COLOR = Color4(240, 24, 24, 255)

local INTERSECTION_NODE_NAME = 'xyz range selector intersection node'
local MAX_RESONABLE_DRAG_DISTANCE = 512
local MODEL_OFFSET = Point3(0.5, 0, 0.5)
local RENDER_INFLATION = Point3(-0.02, -0.02, -0.02)
local TERRAIN_NODES = 1

function XYZRangeSelector:__init(reason)
   self._reason = tostring(reason)
   self._state = 'start'
   self._ruler_color_valid = Color4(255, 255, 255, 128)
   self._ruler_color_invalid = Color4(255, 0, 0, 128)
   self._require_supported = false
   self._require_unblocked = false
   self._show_rulers = true
   self._rotation = 1
   self._length = 0
   self._ignore_children = true
   self._select_front_brick = true
   self._validation_offset = Point3(0, 0, 0)
   self._allow_select_cursor = false
   self._allow_unselectable_support_entities = false
   self._ignore_middle_collision = false
   self._can_pass_through_terrain = false
   self._can_pass_through_buildings = false
   self._invalid_cursor = INVALID_CURSOR
   self._remove_cursor = REMOVE_CURSOR
   self._model_offset = MODEL_OFFSET
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

   self._cursor_fn = function(selected_cube, normal)
      if self:is_current_rotation_in_use() then
         return self._remove_cursor
      elseif not selected_cube then
         return self._invalid_cursor
      end
      return self._cursor
   end

   self._last_ignored_entities = {}
   self._ignored_entities = {}

   self:set_render_params()
end

function XYZRangeSelector:_shift_down()
  return _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_LEFT_SHIFT) or
         _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_RIGHT_SHIFT)
end

-- "rotations" are considered relative to this entity (in terms of its position and rotation)
function XYZRangeSelector:set_relative_entity(entity, ignore_children)
   self._relative_entity = entity
   self._ignore_children = ignore_children ~= false   -- default to true

   local mob = entity and entity:get_component('mob')
   self._model_offset = MODEL_OFFSET - (mob and (mob:get_region_origin() - mob:get_model_origin()) or Point3.zero)

   return self
end

-- this is a list of the axes (relative to the entity's rotation) along which the range can be specified
-- it includes their origin point (relative to the entity) and a directional vector point, along with min/max length
-- can also include a terminus point if a different shape than 1x1xN is desired
-- which override the base min/max length
-- { origin = Point3, terminus = Point3, dimension = string, direction = Point3, [min_length = number], [max_length = number], [valid_lengths = {number, ...}] }
function XYZRangeSelector:set_rotations(rotations)
   self._rotations = rotations
   self._rotations_in_use = {}
   self._region_needs_refresh = true
   return self
end

function XYZRangeSelector:get_rotation()
   return self._rotations[self._rotation]
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
   if rotation.valid_lengths then
      return util.get_closest_value(rotation.valid_lengths, self._length)
   else
      local max_length = self:_get_max_length(rotation)
      return math.max(rotation.min_length, math.min(max_length, self._length or max_length))
   end
end

function XYZRangeSelector:_get_max_length(rotation)
   return rotation.max_length or (rotation.valid_lengths and rotation.valid_lengths[#rotation.valid_lengths]) or 0
end

function XYZRangeSelector:set_rotation_in_use(index, in_use)
   self._rotations_in_use[index] = in_use
   if self._rotation == index then
      self._region_needs_refresh = true
   end
   return self
end

function XYZRangeSelector:set_multi_select_enabled(enabled)
   self._multi_select_enabled = enabled
   return self
end

function XYZRangeSelector:set_render_params(material, color, cancel_color)
   self._render_material = material or '/stonehearth/data/horde/materials/transparent_box_nodepth.material.json'
   self._render_color = color or DEFAULT_BOX_COLOR
   self._render_cancel_color = cancel_color or DEFAULT_CANCEL_BOX_COLOR
   return self
end

function XYZRangeSelector:set_custom_render_fn(custom_fn, disable_default_render)
   self._render_custom_fn = custom_fn
   self._disable_default_render = custom_fn and disable_default_render
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

function XYZRangeSelector:set_ignore_middle_collision(value)
   self._ignore_middle_collision = value
   return self
end

-- "pass_through" refers to the middle section
function XYZRangeSelector:set_can_pass_through_terrain(value)
   self._can_pass_through_terrain = value
   return self
end

function XYZRangeSelector:set_can_pass_through_buildings(value)
   self._can_pass_through_buildings = value
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

function XYZRangeSelector:set_remove_cursor(remove_cursor)
   self._remove_cursor = remove_cursor
   return self
end

function XYZRangeSelector:set_cursor_fn(cursor_fn)
   self._cursor_fn = cursor_fn
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
         node.vis_node:destroy()
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
            --log:debug('location %s is not valid because it contains %s', brick, entity)
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

         --log:debug('getting brick at %s, %s: %s "%s" %s', x, y, tostring(entity), tostring(result.node_name), tostring(result.brick))
         if self._relative_entity then
            if radiant.entities.is_child_of(entity, self._relative_entity) then
               --log:debug('ignoring child entity %s', entity)
               return stonehearth.selection.FILTER_IGNORE
            end
            --log:debug('checking relative entity %s', self._relative_entity)
         elseif self._can_contain_entity_filter_fn and self._can_contain_entity_filter_fn(entity, self) then
            return stonehearth.selection.FILTER_IGNORE
         end

         for i, node in ipairs(self._intersection_nodes) do
            if result.node_name == node.name then
               -- we hit an intersection node created by the user to catch points floating in air
               -- check to see if it's a valid location otherwise
               return self._rotations_in_use[i] or self:_is_valid_location(result.brick)
            end
         end

         return false
      end)
   return brick, normal
end

function XYZRangeSelector:_update()
   if not self._action then
      return
   end

   if self._action == 'reject' then
      self:reject({ error = 'selection cancelled' }) -- is this still the correct argument?
      return
   end

   local current_region = self:get_current_region()
   self._camera_forward = _radiant.renderer.get_camera():get_forward()

   self:_update_rulers(current_region, self._camera_forward)
   self:_update_cursor(current_region, self._camera_forward)

   --local rotation = self:get_rotation()
   local length = self:_get_length()

   if self._action == 'notify' then
      self:notify(false, self._rotation, length, current_region)
   elseif self._action == 'notify_resolve' then
      local region, point, in_use
      in_use = self:is_current_rotation_in_use()
      if not in_use then
         region, point = self:get_region_and_point(length)
      end
      self:notify(true, self._rotation, in_use and 0 or length, region, point)
   elseif self._action == 'resolve' then
      local region, point = self:get_region_and_point(length)
      self:resolve(self._rotation, length, region, point)
   else
      log:error('uknown action: %s', self._action)
      assert(false)
   end
end

function XYZRangeSelector:_world_to_local(pt, entity)
   local mob = entity:add_component('mob')
   local region_origin = mob:get_region_origin()
   --local new_pt = (pt - mob:get_world_grid_location() - region_origin):rotated(-mob:get_facing()) + region_origin
   local new_pt = (pt - mob:get_world_grid_location()):rotated(-mob:get_facing())

   --log:debug('world_to_local for %s: %s => %s', entity, pt, new_pt)
   return new_pt
end

function XYZRangeSelector:_local_to_world(pt)
   local entity = self._relative_entity
   if not entity then
      return pt
   end
   
   local mob = entity:add_component('mob')
   local new_pt = pt:rotated(-mob:get_facing()) + mob:get_world_grid_location()

   return new_pt
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
      if self._multi_select_enabled then
         self._action = 'notify_resolve'
         event_consumed = true
      else
         self._action = 'resolve'
         event_consumed = true
      end
   else
      self._action = 'notify'

      local brick, normal = self:_get_brick_at(event.x, event.y)

      if brick and brick ~= self._last_brick then
         self._last_brick = brick
         local local_brick = self._relative_entity and self:_world_to_local(brick, self._relative_entity) or brick

         -- search intersection nodes for which rotation this could be
         local rotation_index
         for i, node in ipairs(self._intersection_nodes) do
            if node.cube:contains(local_brick) then
               --log:debug('found brick %s in intersection node %s (%s)', local_brick, node.name, node.cube)
               rotation_index = i
               break
            end
         end

         if rotation_index then
            self:set_rotation(rotation_index)
            local rotation = self:get_rotation()
            --local node = self._intersection_nodes[rotation_index]
            local cube = csg_lib.create_min_cube(rotation.origin, local_brick + rotation.terminus)
            self:set_length(cube:get_size()[rotation.dimension])
         end
      end
   end

   self:_update()

   return event_consumed
end

-- TODO: validate new location using _is_valid_location before actually setting rotation/length
-- still need to be able to cycle through rotations if one is invalid (immediately cycle to next valid one?)
-- should a rotation be valid if only a shorter length works for it and auto-shorten? or just block?
-- handles keyboard events from the input service
function XYZRangeSelector:_on_keyboard_event(e)
   local event_consumed = false
   local deltaRot = 0
   local deltaExt = 0

   local num_rotations = #self._rotations

   if num_rotations > 0 then
      if bindings:is_action_active('build:rotate:left') then
         deltaRot = 1
      elseif bindings:is_action_active('build:rotate:right') then
         deltaRot = num_rotations - 1
      elseif bindings:is_action_active('build:raise_template') then
         deltaExt = 1
      elseif bindings:is_action_active('build:sink_template') then
         deltaExt = -1
      end

      if deltaRot ~= 0 then
         self._action = 'notify'
         local new_rotation = ((self._rotation - 1 + deltaRot) % num_rotations) + 1
         self:set_rotation(new_rotation)
         event_consumed = true
      end

      if deltaExt ~= 0 then
         self._action = 'notify'
         self:set_length(self:_get_length() + deltaExt)
         event_consumed = true
      end
   end

   self:_update()

   return event_consumed
end

function XYZRangeSelector:_update_rulers(region, forward)
   if not self._show_rulers or not self._x_ruler or not self._y_ruler or not self._z_ruler then
      return
   end

   if region then
      local r = self._relative_entity and radiant.entities.local_to_world(region, self._relative_entity) or region
      local bounds = r:get_bounds()
      local q0, q1 = bounds.min, bounds.max

      local rotation = self:get_rotation()
      if rotation then
         -- we only care about the ruler for the current rotation's dimension
         for _, d in ipairs({'x', 'y', 'z'}) do
            local ruler = self['_' .. d .. '_ruler']
            if d == rotation.dimension then
               self:_update_ruler(ruler, q0, q1, d, forward)
            else
               ruler:hide()
            end
         end

         return
      end
   end

   self._x_ruler:hide()
   self._y_ruler:hide()
   self._z_ruler:hide()
end

function XYZRangeSelector:_update_ruler(ruler, p0, p1, dimension, forward)
   local d = dimension
   local start = Point3(p1)
   local finish = Point3(p0)
   if forward.x >= 0 then
      start.x, finish.x = finish.x, start.x
   end
   if forward.z >= 0 then
      start.z, finish.z = finish.z, start.z
   end
   
   -- TODO: is forward backward?!
   local normal
   if d == 'y' then
      normal = self:_get_normal_from_forward(forward)
      -- we determine a normal vector on the x-z plane
      -- then we determine the orthogonal dimension to that vector
      -- change the start point so that its value in that orthogonal dimension is instead the finish point's value
      -- this implementation is a hacky way of avoiding actually determining the dimension, and just applying the change to both x and z
      start.x = start.x + math.abs(normal.z) * (finish.x - start.x)
      start.z = start.z + math.abs(normal.x) * (finish.z - start.z)
   else
      normal = Point3(0, 0, 0)
      local dn = d == 'x' and 'z' or 'x'
      normal[dn] = forward[dn] >= 0 and -1 or 1
   end

   local min = math.min(p0[d], p1[d])
   local max = math.max(p0[d], p1[d])
   local length = math.floor(max - min + 0.5)
   if length <= 1 then
      ruler:hide()
      return
   end

   local color = self._ruler_color_valid --or self._ruler_color_invalid
   ruler:set_color(color)

   ruler:set_points(start, finish, dimension, normal, string.format('%d', length))
   ruler:show()
end

function XYZRangeSelector:_get_normal_from_forward(forward)
   local dim = math.abs(forward.x) > math.abs(forward.z) and 'z' or 'x'
   local normal = Point3(0, 0, 0)
   normal[dim] = forward[dim] >= 0 and -1 or 1
   return normal
end

function XYZRangeSelector:_update_cursor(box, forward)
   local normal = self:_get_normal_from_forward(forward)
   local cursor = self._cursor_fn and self._cursor_fn(box, normal)

   if cursor == self._current_cursor then
      return
   end

   self._current_cursor = cursor

   if self._cursor_obj then
      self._cursor_obj:destroy()
      self._cursor_obj = nil
   end

   if cursor then
      self._cursor_obj = _radiant.client.set_cursor(cursor)
   end
end

function XYZRangeSelector:get_point_in_current_direction(distance)
   local rotation = self:get_rotation()
   if rotation then
      distance = math.max(0, distance)
      -- if we're going in a negative direction, we need to shift our point one further in that direction
      if rotation.direction.x < 0 or rotation.direction.z < 0 then
         distance = distance + 1
      end
      return rotation.origin + rotation.direction * distance
   end
end

function XYZRangeSelector:_recalc_current_region(is_final)
   local rotation = self:get_rotation()
   local length = self:_get_length()
   local node = self._intersection_nodes[self._rotation]
   local region

   if length and rotation and node and length > 0 then
      local cube
      if length > 0 then
         local origin = rotation.origin
         if self._ignore_middle_collision and is_final then
            origin = origin + rotation.direction * (length - 1)
         end
         cube = csg_lib.create_min_cube(origin, rotation.terminus + rotation.direction * length)
         --log:debug('_recalc_current_region cube: %s', cube)
      end

      -- make sure there are no entities with collision in this cube (or check custom filter)
      local cube_is_good = true
      if cube then
         local world_cube = self._relative_entity and radiant.entities.local_to_world(cube, self._relative_entity) or cube
         local entities = radiant.terrain.get_entities_in_cube(world_cube)
         local terrain_entity_id = radiant._root_entity_id
         for _, entity in pairs(entities) do
            -- prioritize the simplest checks
            if self._can_pass_through_terrain and entity:get_id() == terrain_entity_id then
               -- ignore
            elseif self._can_pass_through_buildings and entity:get_component('stonehearth:build2:structure') then
               -- ignore
            elseif self._relative_entity and (self._relative_entity == entity or
               (self._ignore_children and radiant.entities.is_child_of(entity, self._relative_entity))) then
               -- ignore
            elseif self._can_contain_entity_filter_fn and not self._can_contain_entity_filter_fn(entity, self) then
               --log:debug('entity %s failed can_contain_entity_filter', entity)
               cube_is_good = false
               break
            else
               local rcs = entity:get_component('region_collision_shape')
               local rc_type = rcs and rcs:get_region_collision_type()
               if rc_type == RegionCollisionType.SOLID or rc_type == RegionCollisionType.PLATFORM then
                  --log:debug('entity %s failed collision check', entity)
                  cube_is_good = false
                  break
               end
            end
         end
      end

      if cube_is_good then
         region = Region3()
         if cube then
            region:add_cube(cube)
         end
      end
   end

   return region
end

function XYZRangeSelector:_add_point_if_not_solid(region, local_point)
   local world_point = self:_local_to_world(local_point)
   if not radiant.entities.is_solid_location(world_point) then
      region:add_cube(Cube3(local_point))
   end
end

function XYZRangeSelector:get_current_region()
   if not self._current_region or self._region_needs_refresh then
      self._region_needs_refresh = false
      self._current_region = self:_recalc_current_region()
      self:_update_render()
   end

   return self._current_region
end

function XYZRangeSelector:get_region_and_point(length)
   local point = self:get_point_in_current_direction(length)
   return self:_recalc_current_region(true), point
end

function XYZRangeSelector:get_current_connector_region()
   local rotation = self:get_rotation()
   if rotation.connector_region then
      local length = self:is_current_rotation_in_use() and 0 or self:_get_length()
      local offset = rotation.direction * length
      return rotation.connector_region:translated(offset)
   end
end

function XYZRangeSelector:is_current_rotation_in_use()
   return self._rotations_in_use[self._rotation]
end

function XYZRangeSelector:_update_render()
   if self._render_node then
      self._render_node:destroy()
      self._render_node = nil
   end

   if not self._disable_default_render and self._render_material and self._current_region then
      local color = self:is_current_rotation_in_use() and self._render_cancel_color or self._render_color
      local render_node = self._relative_entity and _radiant.client.get_render_entity(self._relative_entity):get_node() or RenderRootNode
      self._render_node = _radiant.client.create_region_outline_node(render_node, self._current_region:translated(self._model_offset):inflated(RENDER_INFLATION),
                           radiant.util.to_color4(color, 192),   -- edge color
                           radiant.util.to_color4(color, 192),   -- fill color
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

   local entity_render_node = self._relative_entity and _radiant.client.get_render_entity(self._relative_entity):get_node()
   if self._show_rulers then
      self._x_ruler = XYZRulerWidget()--:set_base_node(entity_render_node)
      self._y_ruler = XYZRulerWidget()--:set_base_node(entity_render_node)
      self._z_ruler = XYZRulerWidget()--:set_base_node(entity_render_node)
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
      local terminus = rotation.terminus
      local render_node = entity_render_node or RenderRootNode
      local min_point = origin + self._model_offset
      local max_point = terminus + self._model_offset + rotation.direction * self:_get_max_length(rotation)
      local cube = csg_lib.create_min_cube(min_point, max_point)
      local name = INTERSECTION_NODE_NAME .. i

      local vis_node = _radiant.client.create_region_outline_node(render_node, Region3(cube:inflated(RENDER_INFLATION * 2)),
                           radiant.util.to_color4(Point3(255, 255, 255), 64), -- edge color
                           radiant.util.to_color4(Point3(255, 255, 255), 24), -- fill color
                           self._render_material, 1)
                           --:set_name(name)
                           :set_visible(true)
                           :set_can_query(false)

      -- need to adjust cube to a full voxel height in case it is a partial voxel
      -- need to have this separate voxel node so that the node name can be properly set
      -- (region outline nodes have random "mesh" names in _radiant.client.query_scene(...) results)
      local int_min = Point3(math.floor(cube.min.x), math.floor(cube.min.y), math.floor(cube.min.z))
      local int_max = Point3(math.ceil(cube.max.x), math.ceil(cube.max.y), math.ceil(cube.max.z))
      local int_cube = Cube3(int_min, int_max)
      local node = _radiant.client.create_voxel_node(render_node, Region3(int_cube), '', MODEL_OFFSET)
                           :set_name(name)
                           :set_visible(false)
                           :set_can_query(true)

      table.insert(nodes, {
         min_point = min_point,
         cube = int_cube,
         name = name,
         node = node,
         vis_node = vis_node
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
                                 return self:_on_keyboard_event(e)
                              end)

   -- TODO: want to be able to call this
   -- self._input_capture:push_object_state()

   -- Report that the xz_region_selector is setup, this is for the auto tests.
   --radiant.events.trigger(radiant, 'radiant:xz_region_selector:go', self._reason, self)

   return self
end

return XYZRangeSelector
