local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2
local Color4 = _radiant.csg.Color4
local validator = radiant.validator
local farming_lib = require 'stonehearth_ace.lib.farming.farming_lib'
local log = radiant.log.create_logger('farming_call_handler')

local AceFarmingCallHandler = class()

-- store this outside the choose_new_field_location function so it doesn't reset after each farm placement
local rotation = 0

function AceFarmingCallHandler:choose_new_field_location(session, response, field_type)
   _radiant.call('stonehearth_ace:get_biome_data')
      :done(function(result)
            self:_choose_new_field_location(session, response, field_type, result.biome_data)
         end)
      :fail(function()
            response:reject('failed to get biome data')
         end)
end

function AceFarmingCallHandler:_choose_new_field_location(session, response, field_type, biome_data)
   local bindings = _radiant.client.get_binding_system()
   local orig_rotation = rotation
   local prev_box, prev_rotation, selector
   
   local max_elevation = biome_data.max_farm_elevation
   local min_elevation = biome_data.min_farm_elevation
   
   field_type = field_type or 'farm'
   local data = radiant.resources.load_json('stonehearth:farmer:all_crops').field_types or {}
   local field_data = data[field_type] or {}
   local size = field_data.size or {}
   local max_size = size.max or 11
   local color = Color4(unpack(field_data.color or {55, 187, 56, 255}))
   local sample_crop = field_data.sample_crop or 'stonehearth:crops:carrot_crop'
   local crop_data = radiant.entities.get_component_data(sample_crop, 'stonehearth:crop')
   local harvest_stage = crop_data and crop_data.harvest_threshhold
   local pattern = field_data.pattern or farming_lib.DEFAULT_PATTERN
   local border = field_data.border or 0
   local max_size_interior = max_size - border * 2
   local valid_terrain = field_data.terrain or {grass = true, dirt = true}

   local crop_entities = {}
   local crops = {}
   for x = 1, max_size do
      local row = {}
      for y = 1, max_size do
         local xb, yb = x - border, y - border
         if xb < 1 or yb < 1 or xb > max_size_interior or yb > max_size_interior then
            row[y] = false
         elseif farming_lib.get_location_type(pattern, xb, yb) == farming_lib.LOCATION_TYPES.CROP then
            local entity = radiant.entities.create_entity(sample_crop)
            entity:add_component('region_collision_shape'):set_region_collision_type(_radiant.om.RegionCollisionShape.NONE)
            if harvest_stage then
               entity:get_component('render_info'):set_model_variant(harvest_stage)
            end
            row[y] = entity
            crop_entities[entity] = false
         else
            row[y] = false
         end
      end
      crops[x] = row
   end

   local hide_crop_nodes = function()
      for crop_entity, _ in pairs(crop_entities) do
         local render_entity = _radiant.client.get_render_entity(crop_entity)
         if render_entity and render_entity:is_valid() then
            render_entity:get_node():set_visible(false)
         end
      end
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

      -- just in case poorly formatted valid_vals
      return val
   end

   local get_proposed_points_fn = function(p0, p1)
      if not p0 or not p1 then
         return nil, nil
      end
      return Point3(p0), Point3(p1)
   end

   local get_resolved_points_fn = get_proposed_points_fn
   if size.valid_x or size.valid_y then
      -- if size specifies only specific valid x/y dimensions, limit to those
      get_resolved_points_fn = function(p0, p1)
         if not p0 or not p1 then
            return nil, nil
         end

         -- if we haven't selected the second point yet, just return the original (identical) points
         if not selector:is_state('p0_selected') then
            return Point3(p0), Point3(p1)
         end
         
         -- get current size; have to consider rotation
         local length = p1 - p0
         local x = math.abs(length.x) + 1
         local y = math.abs(length.z) + 1
         if rotation == 1 or rotation == 3 then
            x, y = y, x
         end

         -- check each axis to see if the dimension is valid
         -- if it's not valid, get the closest valid value
         if size.valid_x then
            x = get_valid_axis_value(size.valid_x, x)
         end
         if size.valid_y then
            y = get_valid_axis_value(size.valid_y, y)
         end

         -- then we have to switch it back to the rotation/direction
         if rotation == 1 or rotation == 3 then
            x, y = y, x
         end

         local q0, q1 = Point3(p0), Point3(p1)
         local sign_x = length.x < 0 and -1 or 1
         local sign_z = length.z < 0 and -1 or 1
         q1.x = q0.x + sign_x * (x - 1)
         q1.z = q0.z + sign_z * (y - 1)

         return q0, q1
      end
   end

   selector = stonehearth.selection:select_designation_region(stonehearth.constants.xz_region_reasons.NEW_FIELD)
      :set_min_size(size.min or 1)
      :set_max_size(max_size)
      :set_keyboard_event_handler(function(e)
            if bindings:is_action_active('build:rotate:left') then
               rotation = (rotation + 1) % 4
               selector:set_requires_recalculation(true)
               return true
            elseif bindings:is_action_active('build:rotate:right') then
               rotation = (rotation + 3) % 4
               selector:set_requires_recalculation(true)
               return true
            end
         end)
      :set_end_point_transforms(get_proposed_points_fn, get_resolved_points_fn)
      :use_manual_marquee(function(xz_region_selector, box, start_location, stabbed_normal)
            -- this first section is the default marquee that we also want to render
            -- save these to be sent to the presence service to render on other players' clients
            local region_shape = box
            local region_type = 'Region2'
            -- recreate the render node for the designation
            local size = box:get_size()
            local region = Region2(Rect2(Point2.zero, Point2(size.x, size.z)))
            local render_node = _radiant.client.create_designation_node(RenderRootNode, region, color, color):set_position(box.min)

            -- now add/remove crop entities based on size
            -- only adjust them if the selection box has actually changed size
            if xz_region_selector:is_state('p0_selected') and (not prev_box or prev_box.min ~= box.min or prev_box.max ~= box.max or prev_rotation ~= rotation) then
               prev_box = box
               prev_rotation = rotation
               local xb_max, yb_max = size.x - border * 2, size.z - border * 2

               hide_crop_nodes()

               for x = 1, max_size do
                  for y = 1, max_size do
                     local xb, yb = x - border, y - border
                     if xb >= 1 and yb >= 1 and xb <= xb_max and yb <= yb_max then
                        local rot_x, rot_y = farming_lib.get_crop_coords(size.x, size.z, rotation, x, y)
                        --log:debug('get_crop_coords(%s, %s, %s, %s) = %s, %s', radiant.util.table_tostring(size), rotation, x, y, rot_x, rot_y)
                        local crop = crops[rot_x][rot_y]
                        if crop then
                           local location = box.min + Point3(x - 1, 0, y - 1)
                           if location.x < box.max.x and location.z < box.max.z then
                              radiant.terrain.place_entity_at_exact_location(crop, location, {force_iconic = false})
                              if not crop_entities[crop] then
                                 crop_entities[crop] = _radiant.client.trace_render_frame()
                                    :on_frame_start('adjust crop entity', function(now, alpha, frame_time, frame_time_wallclock)
                                          local render_entity = _radiant.client.get_render_entity(crop)
                                          if render_entity and render_entity:is_valid() then
                                             render_entity:get_node():set_can_query(false)
                                             render_entity:get_node():set_visible(true)
                                             render_entity:get_model():set_material('materials/always_on_top_obj.material.json', true)
                                             render_entity:get_model():get_material():set_vector_parameter('widgetColor', color.r / 255.0, color.g / 255.0, color.b / 255.0, 0.6)
                                             crop_entities[crop]:destroy()
                                             crop_entities[crop] = false
                                          end
                                       end)
                              end
                           end
                        end
                     end
                  end
               end
            end

            return render_node, region_shape, region_type
         end)
      :set_cursor(field_data.cursor or 'stonehearth:cursors:zone_farm')
      :set_find_support_filter(function(result)
         local entity = result.entity
         local brick = result.brick

         if min_elevation and brick.y < min_elevation then
            return false
         end

         if max_elevation and brick.y > max_elevation then
            return false
         end
   
         local rcs = entity:get_component('region_collision_shape')
         local region_collision_type = rcs and rcs:get_region_collision_type()
         if region_collision_type == _radiant.om.RegionCollisionShape.NONE then
            return stonehearth.selection.FILTER_IGNORE
         end
   
         if entity:get_id() ~= radiant._root_entity_id then
            return false
         end
   
         local tag = radiant.terrain.get_block_tag_at(brick)
         local kind = radiant.terrain.get_block_kind_from_tag(tag)
         local name = radiant.terrain.get_block_name_from_tag(tag)
         local is_valid = valid_terrain[kind] or valid_terrain[name]
         return is_valid
      end)
      :restart(function(selector)
            hide_crop_nodes()
         end)
      :done(function(selector, box)
            local size = {
               x = box.max.x - box.min.x,
               y = box.max.z - box.min.z,
            }
            _radiant.call('stonehearth:create_new_field', box.min, size, field_type, rotation)
                     :done(function(r)
                           response:resolve({ field = r.field })
                        end)
                     :always(function()
                           selector:destroy()
                        end)
         end)
      :fail(function(selector)
            -- local q0, q1 = selector:_find_valid_region(selector._p0, selector._p1)
            -- local is_valid_region = q0 == selector._p0 and q1 == selector._p1

            -- local valid_dimensions = is_valid_region and selector:_are_valid_dimensions(selector._p0, selector._p1)
            -- log:debug('placing field failed! %s, %s, %s, %s, %s, %s, %s, %s\n%s', field_type, radiant.util.table_tostring(prev_box),
            --       selector._p0, selector._p1, q0, q1, tostring(is_valid_region), tostring(valid_dimensions), radiant.util.table_tostring(crop_entities))
            selector:destroy()
            response:reject('no region')
            rotation = orig_rotation
         end)
      :always(function()
            for crop_entity, render_trace in pairs(crop_entities) do
               if render_trace then
                  render_trace:destroy()
               end
               radiant.entities.destroy_entity(crop_entity)
            end
            crops = nil
            crop_entities = nil
         end)
      :go()
end

function AceFarmingCallHandler:create_new_field(session, response, location, size, field_type, rotation)
   validator.expect_argument_types({'Point3', 'table', 'string', 'number'}, location, size, field_type, rotation)
   local data = radiant.resources.load_json('stonehearth:farmer:all_crops').field_types or {}
   local field_data = data[field_type] or {}
   local field_size = field_data.size or {}

   validator.expect.num.range(size.x, field_size.min or 1, field_size.max or 11)
   validator.expect.num.range(size.y, field_size.min or 1, field_size.max or 11)

   local entity = stonehearth.farming:create_new_field(session, location, size, field_type, rotation)
   response:resolve({ field = entity })
end

return AceFarmingCallHandler