local validator = radiant.validator
local FarmingCallHandler = class()

function FarmingCallHandler:set_farm_fertilizer_preference(session, response, field, preference)
   validator.expect_argument_types({'Entity', 'table'}, field, preference)

   if session.player_id ~= field:get_player_id() then
      response:reject('player does not own this field')
      return false
   else
      local farmer_field = field:get_component('stonehearth:farmer_field')
      farmer_field:set_fertilizer_preference(preference)
      response:resolve({})
      return true
   end
end

return FarmingCallHandler