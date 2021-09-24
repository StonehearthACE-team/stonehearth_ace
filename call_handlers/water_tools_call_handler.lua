local RegionCollisionType = _radiant.om.RegionCollisionShape
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local validator = radiant.validator

local WaterToolsCallHandler = class()

local log = radiant.log.create_logger('water_tools_call_handler')

function WaterToolsCallHandler:select_water_pump_pipe_command(session, response, pump)
   validator.expect_argument_types({'Entity'}, pump)

   local rotations = radiant.util.get_rotations_table(radiant.entities.get_component_data(pump, 'stonehearth_ace:water_pump'))
   if #rotations < 1 then
      response:reject({})
      return
   end

   local can_contain_uris = {
      ['stonehearth:terrain:water'] = true,
      ['stonehearth:terrain:waterfall'] = true,
   }

   stonehearth.selection:select_xyz_range('water_pump_pipe_range_selector')
      --:set_cursor('stonehearth:cursors:fence')
      :set_relative_entity(pump)
      :set_rotations(rotations)
      :require_unblocked(true)
      :set_can_pass_through_terrain(true)
      :set_can_pass_through_buildings(true)
      :set_ignore_middle_collision(false) -- we still want to block on other entities with collision
      :set_can_contain_entity_filter(
         function(entity, selector)
            return can_contain_uris[entity:get_uri()]
         end
      )
      :done(
         function(selector, rotation_index, length, region, output_point)
            local output_origin = selector:get_point_in_current_direction(length - 1)
            _radiant.call('stonehearth_ace:set_water_pump_pipe_command', pump, rotation_index, length, region, output_point, output_origin)
               :done(
                  function(r)
                     response:resolve({})
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
      :go()
end

function WaterToolsCallHandler:set_water_pump_pipe_command(session, response, pump, rotation_index, length, region_table, output_point, output_origin)
   -- apparently Region3 parameters get turned into tables and have to be loaded
   validator.expect_argument_types({'Entity', 'number', 'number', 'table', 'Point3', 'Point3'}, pump, rotation_index, length, region_table, output_point, output_origin)

   local region = Region3()
   region:load(region_table)

   local pump_comp = pump:get_component('stonehearth_ace:water_pump')
   local sponge_comp = pump:get_component('stonehearth_ace:water_sponge')

   if pump_comp then
      pump_comp:set_pipe_extension(rotation_index, length, region)
   end

   if sponge_comp then
      -- also apparently a Point3 isn't actually a Point3
      sponge_comp:set_output_location(radiant.util.to_point3(output_point), radiant.util.to_point3(output_origin))
   end

   response:resolve({})
end

function WaterToolsCallHandler:remove_water_pump_pipe_command(session, response, pump)
   validator.expect_argument_types({'Entity'}, pump)

   local pump_comp = pump:get_component('stonehearth_ace:water_pump')
   local sponge_comp = pump:get_component('stonehearth_ace:water_sponge')

   if pump_comp then
      pump_comp:set_pipe_extension(nil)
   end

   if sponge_comp then
      sponge_comp:set_output_location(nil)
   end

   response:resolve({})
end

function WaterToolsCallHandler:set_water_sponge_flow_enabled(session, response, sponge, input_enabled, output_enabled)
   validator.expect_argument_types({'Entity', validator.optional('boolean'), validator.optional('boolean')}, sponge, input_enabled, output_enabled)

   local sponge_comp = sponge:get_component('stonehearth_ace:water_sponge')

   if sponge_comp then
      sponge_comp:set_enabled(input_enabled, output_enabled)
   end

   response:resolve({})
end

return WaterToolsCallHandler
