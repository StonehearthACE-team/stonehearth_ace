local Entity = _radiant.om.Entity
local validator = radiant.validator

local TransformCallHandler = class()

function TransformCallHandler:transform_command(session, response, entity, transform_key)
   validator.expect_argument_types({'Entity'}, entity)

   local transform_comp = entity:get_component('stonehearth_ace:transform')
   if transform_comp then
      transform_comp:set_transform_option(transform_key)
      transform_comp:request_transform(session.player_id)
   else
      return false
   end
end

return TransformCallHandler