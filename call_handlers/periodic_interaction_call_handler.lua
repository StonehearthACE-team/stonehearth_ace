local validator = radiant.validator
local PeriodicInteractionCallHandler = class()

function PeriodicInteractionCallHandler:set_periodic_interaction_enabled(session, response, entity, enabled)
   validator.expect_argument_types({'Entity'}, entity)
   
   entity:add_component('stonehearth_ace:periodic_interaction'):set_enabled(enabled)
end

function PeriodicInteractionCallHandler:set_periodic_interaction_mode(session, response, entity, mode)
   validator.expect_argument_types({'Entity', 'string'}, entity, mode)
   
   entity:add_component('stonehearth_ace:periodic_interaction'):select_mode(mode)
end

return PeriodicInteractionCallHandler
