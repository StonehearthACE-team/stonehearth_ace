local Entity = _radiant.om.Entity
local validator = radiant.validator

local WaterToolsCallHandler = class()

local log = radiant.log.create_logger('water_tools_call_handler')

function WaterToolsCallHandler:set_water_sponge_flow_enabled(session, response, sponge, input_enabled, output_enabled)
   validator.expect_argument_types({'Entity', validator.optional('boolean'), validator.optional('boolean')}, sponge, input_enabled, output_enabled)

   local sponge_comp = sponge:get_component('stonehearth_ace:water_sponge')

   if sponge_comp then
      sponge_comp:set_enabled(input_enabled, output_enabled)
   end

   response:resolve({})
end

return WaterToolsCallHandler
