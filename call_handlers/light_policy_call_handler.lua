local Entity = _radiant.om.Entity
local validator = radiant.validator

local LightPolicyCallHandler = class()

function LightPolicyCallHandler:set_light_policy_command(session, response, entity, light_policy)
   validator.expect_argument_types({'Entity'}, entity)

   local lamp_component = entity:get_component('stonehearth:lamp')
   if lamp_component then
      lamp_component:set_light_policy(light_policy)
      lamp_component:_check_light()
   else
      return false
   end
end

return LightPolicyCallHandler