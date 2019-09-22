local Color4 = _radiant.csg.Color4
local validator = radiant.validator

local AceFarmingCallHandler = class()

function AceFarmingCallHandler:choose_new_field_location(session, response, field_type)
   field_type = field_type or 'farm'
   local data = radiant.resources.load_json('stonehearth:farmer:all_crops').field_types or {}
   local field_data = data[field_type] or {}
   local size = field_data.size or {}
   local color = Color4(unpack(field_data.color or {55, 187, 56, 255}))

   -- TODO: set custom marquee to render sample crop at plot points (similar to fence tool)
   stonehearth.selection:select_designation_region(stonehearth.constants.xz_region_reasons.NEW_FIELD)
      :set_min_size(size.min or 1)
      :set_max_size(size.max or 11)
      :use_designation_marquee(color)
      :set_cursor(field_data.cursor or 'stonehearth:cursors:zone_farm')
      :set_find_support_filter(stonehearth.selection.valid_terrain_blocks_only_xz_region_support_filter(field_data.terrain or {
            grass = true,
            dirt = true
         }))

      :done(function(selector, box)
            local size = {
               x = box.max.x - box.min.x,
               y = box.max.z - box.min.z,
            }
            _radiant.call('stonehearth:create_new_field', box.min, size, field_type)
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
      :go()
end

function AceFarmingCallHandler:create_new_field(session, response, location, size, field_type)
   validator.expect_argument_types({'Point3', 'table', 'string'}, location, size, field_type)
   local data = radiant.resources.load_json('stonehearth:farmer:all_crops').field_types or {}
   local field_data = data[field_type] or {}
   local field_size = field_data.size or {}

   validator.expect.num.range(size.x, field_size.min or 1, field_size.max or 11)
   validator.expect.num.range(size.y, field_size.min or 1, field_size.max or 11)

   local entity = stonehearth.farming:create_new_field(session, location, size, field_type)
   return { field = entity }
end

return AceFarmingCallHandler