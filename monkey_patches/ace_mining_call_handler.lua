local constants = require 'stonehearth.constants'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('mining')
local validator = radiant.validator

-- File-level globals to keep state between invocations.
local current_custom_block_size_horizontal = 1
local current_custom_block_size_vertical = 1

local AceMiningCallHandler = class()

function aligned_floor(value, align)
   return math.floor(value / align) * align
end

function aligned_ceil(value, align)
   return math.ceil(value / align) * align
end

function get_cell_min(value, cell_size)
   return aligned_floor(value, cell_size)
end

function get_cell_max(value, cell_size)
   return get_cell_min(value, cell_size) + cell_size-1
end

function AceMiningCallHandler:designate_mining_zone(session, response, tool_mode, bid)
   validator.expect_argument_types({'string'}, tool_mode)

   local xz_cell_size = constants.mining.XZ_CELL_SIZE
   local y_cell_size = constants.mining.Y_CELL_SIZE
   local clip_enabled = stonehearth.subterranean_view:get_clip_enabled()
   local aligned = false

   if tool_mode == 'cube' then
      aligned = true
   end

   local get_proposed_points = function(p0, p1, normal)
      if not self:_valid_endpoints(p0, p1) then
         return nil, nil
      end

      local mode = self:_get_mode(p0, normal)
      local y_offset = self:_get_y_offset(mode)
      local y = get_cell_max(p0.y, y_cell_size) + y_offset
      local q0 = Point3(p0.x, y, p0.z)
      local q1 = Point3(p1.x, y, p1.z)

      -- Expand q0 and q1 so they span the the quantized region
      for _, d in ipairs({ 'x', 'z' }) do
         if q0[d] <= q1[d] then
            q0[d] = get_cell_min(q0[d], xz_cell_size)
            q1[d] = get_cell_max(q1[d], xz_cell_size)
         else
            q0[d] = get_cell_max(q0[d], xz_cell_size)
            q1[d] = get_cell_min(q1[d], xz_cell_size)
         end
      end
      log:spam('proposed point transform: %s, %s -> %s, %s', p0, p1, q0, q1)

      return q0, q1
   end

   local get_resolved_points = function(p0, p1, normal)
      if not self:_valid_endpoints(p0, p1) then
         return nil, nil
      end

      assert(p0.y == p1.y)
      local q0 = Point3(p0)
      local q1 = Point3(p1)

      -- Contract q1 to the largest quantized region that fits inside the validated region.
      -- q0's final location is the same as the proposed location, which must be valid
      -- or we wouldn't be asked to resolve.
      for _, d in ipairs({ 'x', 'z' }) do
         if q0[d] <= q1[d] then
            if q0[d] ~= get_cell_min(q0[d], xz_cell_size) then
               -- validated point does not span the cell, bail
               return nil, nil
            end

            q1[d] = aligned_floor(q1[d]+1, xz_cell_size) - 1

            if q1[d] < q0[d] then
               return nil, nil
            end
         else
            if q0[d] ~= get_cell_max(q0[d], xz_cell_size) then
               -- validated point does not span the cell, bail
               return nil, nil
            end

            q1[d] = aligned_ceil(q1[d], xz_cell_size)

            if q0[d] < q1[d] then
               return nil, nil
            end
         end
      end
      log:spam('resolved point transform: %s, %s -> %s, %s', p0, p1, q0, q1)

      return q0, q1
   end

   local get_validated_points = function(p0, p1, normal)
      if not self:_valid_endpoints(p0, p1) then
         return nil, nil
      end
      return p0, p1
   end

   -- Allow growing/shrinking the custom block.
   local is_ctrl_held = function()
      return _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_LEFT_CONTROL)
          or _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_RIGHT_CONTROL)
   end
   local is_alt_held = function()
      return _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_LEFT_ALT)
          or _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_RIGHT_ALT)
   end
   local is_shift_held = function()
      return _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_LEFT_SHIFT)
          or _radiant.client.is_key_down(_radiant.client.KeyboardInput.KEY_RIGHT_SHIFT)
   end
   local on_keyboard_event = function(e)
      -- Redraw zone to update color when Ctrl is pressed or released.
      return e.key == _radiant.client.KeyboardInput.KEY_LEFT_CONTROL
          or e.key == _radiant.client.KeyboardInput.KEY_RIGHT_CONTROL
   end

   local on_mouse_event = function(e)
      local result = false
      if e.wheel ~= 0 then
         if is_shift_held() then
            if e.wheel > 0 then
               if current_custom_block_size_horizontal < 8 then
                  current_custom_block_size_horizontal = current_custom_block_size_horizontal + 1
               end
            else
               if current_custom_block_size_horizontal > 1 then
                  current_custom_block_size_horizontal = current_custom_block_size_horizontal - 1
               end
            end
            result = true
         end
         if is_alt_held() then
            if e.wheel > 0 then
               if current_custom_block_size_vertical < 8 then
                  current_custom_block_size_vertical = current_custom_block_size_vertical + 1
               end
            else
               if current_custom_block_size_vertical > 1 then
                  current_custom_block_size_vertical = current_custom_block_size_vertical - 1
               end
            end
            result = true
         end
      end
      return result
   end

   local terrain_support_filter = function(selected)
      if selected.entity:get_component('terrain') then
         return true
      end
      if is_ctrl_held() and selected.entity:get_component('stonehearth:mining_zone') then
         -- If we're subtracting, allow targeting existing zones.
         return true
      end
      -- otherwise, keep looking!
      return stonehearth.selection.FILTER_IGNORE
   end

   local contain_entity_filter = function(entity)
      -- allow mining zones to overlap when dragging out the region
      if entity:get_uri() == 'stonehearth:mining_zone_designation' then
         return stonehearth.selection.FILTER_IGNORE
      end

      -- reject other designations  [ACE: ... that don't explicitly allow mining!]
      local designation_data = radiant.entities.get_entity_data(entity, 'stonehearth:designation')
      if designation_data and not designation_data.allow_mining then
         return false
      end

      -- reject solid entities that are not terrain
      local rcs = entity:get_component('region_collision_shape')
      if rcs and rcs:get_region_collision_type() ~= _radiant.om.RegionCollisionShape.NONE then
         return false
      end

      return true
   end

   local draw_region_outline_marquee = function(selector, box, origin, normal)
      local mode = nil
      if aligned then
         mode = self:_infer_mode(box)
      end
      local region = self:_get_dig_region(box, mode, tool_mode, origin, normal, current_custom_block_size_horizontal, current_custom_block_size_vertical)
      
      local color = { x = 255, y = 255, z = 0 } -- ye olde default
      if is_ctrl_held() then
         color = { x = 255, y = 0, z = 0 } -- removal is always red
      else
         if stonehearth.presence_client:is_multiplayer() then
            color = stonehearth.presence_client:get_player_color(_radiant.client.get_player_id())
         end
         if bid then
            -- if it's part of a building id, reduce the green
            color.x = color.x * 0.6
         end
      end
      
      region = region:inflated(Point3(0.001, 0.001, 0.001))  -- Push it out so there's always a floating part.
      
      local render_node
      if tool_mode == 'custom_block' then
         local EDGE_COLOR_ALPHA = 24
         local FACE_COLOR_ALPHA = 6
         render_node = _radiant.client.create_region_outline_node(RenderRootNode, region, radiant.util.to_color4(color, EDGE_COLOR_ALPHA), radiant.util.to_color4(color, FACE_COLOR_ALPHA), 'materials/transparent_box_nodepth.material.json', 'materials/debug_shape_nodepth.material.json', 1)
         local floating_region = Region3(region)
         local terrain_intersection = stonehearth.subterranean_view:intersect_region_with_visible_volume(radiant.terrain.clip_region(region))
         floating_region:subtract_region(terrain_intersection)
         local floating_render_node = _radiant.client.create_region_outline_node(RenderRootNode, floating_region, radiant.util.to_color4(color, EDGE_COLOR_ALPHA * 8), radiant.util.to_color4(color, FACE_COLOR_ALPHA * 4), 'materials/transparent_box.material.json', 'materials/debug_shape.material.json', 1)
         floating_render_node:set_parent(render_node)
         render_node:add_reference_to(floating_render_node)
      else
         -- Simple mining tool shows a simpler cursor preview.
         local EDGE_COLOR_ALPHA = 128
         local FACE_COLOR_ALPHA = 16
         render_node = _radiant.client.create_region_outline_node(RenderRootNode, region, radiant.util.to_color4(color, EDGE_COLOR_ALPHA), radiant.util.to_color4(color, FACE_COLOR_ALPHA), 'materials/transparent_box.material.json', 'materials/debug_shape.material.json', 1)
      end
      
      if tool_mode == 'custom_block' and math.abs(current_custom_block_size_vertical) > 1 then
         local y_label_node = render_node:add_text_node(tostring(math.abs(current_custom_block_size_vertical)))
         y_label_node:set_position(region:get_bounds().max)
         render_node:add_reference_to(y_label_node)
         y_label_node:set_parent(render_node)
      end

      return render_node, region
   end

   local select_cursor = function(box, normal)
      if not box then
         return 'stonehearth:cursors:invalid_hover'
      end

      return 'stonehearth:cursors:mine'
   end

   local ghost_ignored_entity_filter = function(entity)
      if not clip_enabled then
         return false
      end

      local collision_shape_component = entity:get_component('region_collision_shape')
      if not collision_shape_component then
         return false
      end

      local region = collision_shape_component:get_region():get()
      return not region:empty()
   end

   local selector = stonehearth.selection:select_xz_region(stonehearth.constants.xz_region_reasons.MINING)
      :select_front_brick(false)
      :set_max_size(constants.mining.MAX_LENGTH)
      :set_validation_offset(Point3.unit_y)
      :set_cursor_fn(select_cursor)
      :set_find_support_filter(terrain_support_filter)
      :set_can_contain_entity_filter(contain_entity_filter)
      :set_ghost_ignored_entity_filter(ghost_ignored_entity_filter)
      :use_manual_marquee(draw_region_outline_marquee)
      
   if tool_mode == 'custom_block' then
      selector:set_keyboard_event_handler(on_keyboard_event)
              :set_mouse_event_handler(on_mouse_event)
   end

   if aligned then
      selector:set_end_point_transforms(get_proposed_points, get_resolved_points)
   else
      selector:set_end_point_transforms(get_validated_points, get_validated_points)
   end

   selector
      :done(function(selector, box, origin, normal)
            local mode = nil
            if aligned then
               mode = self:_infer_mode(box)
            end
            local region = self:_get_dig_region(box, mode, tool_mode, origin, normal, current_custom_block_size_horizontal, current_custom_block_size_vertical)
            if is_ctrl_held() then
               mode = 'remove'
            end
            -- this is the client, so we can just get the gameplay setting directly from the config
            local start_suspended = radiant.util.get_global_config('mods.stonehearth.default_mining_zones_suspended', false)
            _radiant.call('stonehearth:add_mining_zone', region, mode, { start_suspended = start_suspended, bid = bid })
               :done(function(r)
                     response:resolve({ mining_zone = r.mining_zone })
                     if not stonehearth.subterranean_view:clip_height_initialized() then
                        local clip_height = get_cell_max(box.min.y, constants.mining.Y_CELL_SIZE)
                        stonehearth.subterranean_view:initialize_clip_height(clip_height)
                     end
                  end
               )
               :always(function()
                     selector:destroy()
                  end
               )
         end
      )

      :fail(function(selector)
            selector:destroy()
            response:reject('no region')
         end
      )

      :go()
end

return AceMiningCallHandler
