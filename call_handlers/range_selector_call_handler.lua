local RegionCollisionType = _radiant.om.RegionCollisionShape
local Entity = _radiant.om.Entity
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
local validator = radiant.validator
local water_lib = require 'stonehearth_ace.lib.water.water_lib'

local RangeSelectorCallHandler = class()

local log = radiant.log.create_logger('range_selector_call_handler')

function RangeSelectorCallHandler:select_water_pump_pipe_command(session, response, pump)
   validator.expect_argument_types({'Entity'}, pump)

   local rotations = water_lib.get_water_pump_rotations(pump:get_uri())
   if #rotations < 1 then
      response:reject({})
      return
   end

   stonehearth.selection:select_xyz_range('water_pump_pipe_range_selector')
      --:set_cursor('stonehearth:cursors:fence')
      :set_relative_entity(pump)
      :set_rotations(rotations)
      :done(
         function(selector, rotation_index, length, region, output_point)
            _radiant.call('stonehearth_ace:set_water_pump_pipe_command', rotation_index, length, region, output_point)
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

function RangeSelectorCallHandler:set_water_pump_pipe_command(session, response, pump, rotation_index, length, region, output_point)
   validator.expect_argument_types({'Entity', 'number', 'number', 'Region3', 'Point3'}, pump, rotation_index, length, region, output_point)

   local pump_comp = pump:get_component('stonehearth_ace:water_pump')
   local sponge_comp = pump:get_component('stonehearth_ace:water_sponge')

   if pump_comp then
      pump_comp:set_pipe_extension(rotation_index, length, region)
   end

   if sponge_comp then
      sponge_comp:set_output_location(output_point)
   end

   response:resolve({})
end

return RangeSelectorCallHandler
