local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Rect2 = _radiant.csg.Rect2
local Region2 = _radiant.csg.Region2
local Color4 = _radiant.csg.Color4
local validator = radiant.validator
local constants = require 'stonehearth.constants'
local farming_constants = constants.farming
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
   local pattern = field_data.pattern or farming_constants.DEFAULT_PATTERN
   local border = field_data.border or 0
   local valid_terrain = field_data.terrain or {grass = true, dirt = true}

   stonehearth.selection:select_pattern_designation_region(stonehearth.constants.xz_region_reasons.NEW_FIELD)
      :set_min_size(size.min or 1)
      :set_max_size(max_size)
      :set_valid_dims(size.valid_x, size.valid_y)
      :set_border(border)
      :set_color(color)
      :set_rotation(rotation)
      :set_pattern(pattern, {
         [2] = {
            uri = sample_crop,
            model_variant = harvest_stage,
         }
      })
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