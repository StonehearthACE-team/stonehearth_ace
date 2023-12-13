local validator = radiant.validator
local EntityModificationCallHandler = class()

function EntityModificationCallHandler:cycle_model_variant(session, response, entity)
   validator.expect_argument_types({'Entity'}, entity)

   local entity_modification_component = entity:add_component('stonehearth_ace:entity_modification')
   entity_modification_component:cycle_model_variant()
   return true
end

return EntityModificationCallHandler
