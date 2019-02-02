local validator = radiant.validator

local PastureCallHandler = class()

function PastureCallHandler:set_pasture_harvest_animals_renewable(session, response, pasture, value)
   validator.expect_argument_types({'Entity', 'boolean'}, pasture, value)

   if session.player_id ~= pasture:get_player_id() then
      return false
   else
      local pasture_component = pasture:get_component('stonehearth:shepherd_pasture')
      pasture_component:set_harvest_animals_renewable(value)
      return true
   end
end

function PastureCallHandler:set_pasture_harvest_grass(session, response, pasture, value)
   validator.expect_argument_types({'Entity', 'boolean'}, pasture, value)

   if session.player_id ~= pasture:get_player_id() then
      return false
   else
      local pasture_component = pasture:get_component('stonehearth:shepherd_pasture')
      pasture_component:set_harvest_grass(value)
      return true
   end
end

function PastureCallHandler:set_pasture_maintain_animals(session, response, pasture, value)
   validator.expect_argument_types({'Entity', 'number'}, pasture, value)

   if session.player_id ~= pasture:get_player_id() then
      return false
   else
      local pasture_component = pasture:get_component('stonehearth:shepherd_pasture')
      pasture_component:set_maintain_animals(value)
      return true
   end
end

return PastureCallHandler