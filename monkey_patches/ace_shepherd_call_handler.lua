local Point2 = _radiant.csg.Point2
local Color4 = _radiant.csg.Color4
local validator = radiant.validator

local AceShepherdCallHandler = class()
local log = radiant.log.create_logger('shepherd_call_handler')

function AceShepherdCallHandler:_get_pasture_region_selector(session, response)
   local find_support_filter_fn = stonehearth.selection.valid_terrain_blocks_only_xz_region_support_filter({
      grass = true,
      dirt = true
   })
   local filter_fn = function(result, selector)
      -- require selecting terrain at the same elevation as the first point
      if selector._state == 'p0_selected' and selector._p0.y ~= (result.brick + result.normal).y then
         log:debug('_p0 = %s, result.brick = %s, result.normal = %s', selector._p0, result.brick, result.normal)
         return false
      end
      --log:debug(radiant.util.table_tostring(result))
      local return_val = find_support_filter_fn(result)
      --log:debug('return_val = %s', tostring(return_val))
      return return_val
   end

   local zone_data = radiant.entities.get_component_data('stonehearth:shepherd:shepherd_pasture', 'stonehearth:shepherd_pasture') or {}
   
   return stonehearth.selection:select_designation_region(stonehearth.constants.xz_region_reasons.PASTURE)
      :set_min_size(10)
      :set_max_size(50)
      :require_unblocked(false)
      :use_designation_marquee(Color4(unpack(zone_data.zone_color or {227, 173, 44, 204})))
      :require_supported(false)                    -- ACE: override the default for a designation region selector
      :allow_unselectable_support_entities(false)  -- ACE: override the default for a designation region selector
      :set_create_intersection_node(false)
      :set_find_support_filter(filter_fn)
      :set_can_contain_entity_filter(function(entity)
            -- avoid other designations.
            if radiant.entities.get_entity_data(entity, 'stonehearth:designation') then
               return false
            end
            if entity:get_component('terrain') then
               return false
            end
            return true
         end)
      :set_cursor('stonehearth:cursors:zone_pasture')
      :done(
         function(selector, box)
            local size = {
               x = box.max.x - box.min.x,
               z = box.max.z - box.min.z,
            }
            _radiant.call('stonehearth:create_pasture', box.min, size)
               :done(
                  function(r)
                     response:resolve({ pasture = r.pasture })
                  end
               )
               :always(
                  function()
                     selector:destroy()
                  end
               )
         end
      )
      :fail(
         function(selector)
            selector:destroy()
            response:reject('no region')
         end
      )
end

-- Runs on the client!
function AceShepherdCallHandler:choose_pasture_location(session, response)
   self:_get_pasture_region_selector(session, response):go()
end

return AceShepherdCallHandler
