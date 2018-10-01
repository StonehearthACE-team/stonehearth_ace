local Color4 = _radiant.csg.Color4

local underfarming_service = stonehearth_ace.underfarming
local validator = radiant.validator

local UnderfarmingCallHandler = class()

-- runs on the client!!
function UnderfarmingCallHandler:choose_new_underfield_location(session, response)
   stonehearth.selection:select_designation_region(stonehearth.constants.xz_region_reasons.NEW_FIELD)
      :set_max_size(8)
      :use_designation_marquee(Color4(55, 187, 56, 255))
      :set_cursor('stonehearth:cursors:zone_farm')
      :set_find_support_filter(stonehearth.selection.valid_terrain_blocks_only_xz_region_support_filter({
            rock = true,
            dirt = true
         }))

      :done(function(selector, box)
            local size = {
               x = box.max.x - box.min.x,
               y = box.max.z - box.min.z,
            }
            _radiant.call('stonehearth_ace:create_new_underfield', box.min, size)
                     :done(function(r)
                           response:resolve({ underfield = r.underfield })
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

-- runs on the server!
function UnderfarmingCallHandler:create_new_underfield(session, response, location, size)
   validator.expect_argument_types({'Point3', 'table'}, location, size)
   validator.expect.num.range(size.x, 1, 8)
   validator.expect.num.range(size.y, 1, 8)

   local entity = stonehearth_ace.underfarming:create_new_underfield(session, location, size)
   return { underfield = entity }
end

--TODO: Send an array of substrate_plots and the type of the undercrop for batch planting
function UnderfarmingCallHandler:plant_undercrop(session, response, substrate_plot, undercrop_type, player_specified, auto_plant, auto_harvest)
   validator.expect_argument_types({validator.any_type(), 'string', 'boolean', 'boolean', 'boolean'}, substrate_plot, undercrop_type, player_specified, auto_plant, auto_harvest)
   --TODO: remove this when we actually get the correct data from the UI
   local substrate_plots = {substrate_plot}
   if not undercrop_type then
      undercrop_type = 'stonehearth_ace:undercrops:dwarfoot'
   end

   return underfarming_service:plant_undercrop(session.player_id, substrate_plots, undercrop_type, player_speficied, auto_plant, auto_harvest, true)
end

--- Returns the undercrops available for planting to this player
function UnderfarmingCallHandler:get_all_undercrops(session)
   return {all_undercrops = underfarming_service:get_all_undercrop_types(session)}
end

return UnderfarmingCallHandler
