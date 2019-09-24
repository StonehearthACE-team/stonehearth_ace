local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2
local Color4 = _radiant.csg.Color4
local validator = radiant.validator
local farming_lib = require 'stonehearth_ace.lib.farming.farming_lib'
local log = radiant.log.create_logger('farming_call_handler')

local AceFarmingCallHandler = class()

function AceFarmingCallHandler:choose_new_field_location(session, response, field_type)
   local bindings = _radiant.client.get_binding_system()
   
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

   local crop_entities = {}
   local crops = {}
   for x = 1, max_size do
      local row = {}
      for y = 1, max_size do
         if farming_lib.get_location_type(pattern, x, y) == farming_lib.LOCATION_TYPES.CROP then
            local entity = radiant.entities.create_entity(sample_crop)
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

   local prev_box, prev_rotation
   local rotation = 0
   stonehearth.selection:select_designation_region(stonehearth.constants.xz_region_reasons.NEW_FIELD)
      :set_min_size(size.min or 1)
      :set_max_size(max_size)
      :set_keyboard_event_handler(function(e)
            if bindings:is_action_active('build:rotate:left') then
               rotation = (rotation + 1) % 4
               return true
            elseif bindings:is_action_active('build:rotate:right') then
               rotation = (rotation + 3) % 4
               return true
            end
         end)
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
            if not prev_box or prev_box.min ~= box.min or prev_box.max ~= box.max or prev_rotation ~= rotation then
               prev_box = box
               prev_rotation = rotation

               hide_crop_nodes()

               for x = 1, max_size do
                  for y = 1, max_size do
                     local rot_x, rot_y = farming_lib.get_crop_coords(size.x, size.z, rotation, x, y)
                     --log:debug('get_crop_coords(%s, %s, %s, %s) = %s, %s', radiant.util.table_tostring(size), rotation, x, y, rot_x, rot_y)
                     if rot_x > 0 and rot_y > 0 then
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
      :set_find_support_filter(stonehearth.selection.valid_terrain_blocks_only_xz_region_support_filter(field_data.terrain or {
            grass = true,
            dirt = true
         }))
      :set_can_contain_entity_filter(function(entity)
            for render_entity, _ in pairs(crop_entities) do
               if render_entity == entity then
                  return true
               end
            end
            return false
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
            selector:destroy()
            response:reject('no region')
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
   return { field = entity }
end

return AceFarmingCallHandler