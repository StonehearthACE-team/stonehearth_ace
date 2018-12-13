local Entity = _radiant.om.Entity
local validator = radiant.validator

local CustomTooltipsCallHandler = class()

function CustomTooltipsCallHandler:get_custom_tooltip_command(session, response, item_or_type, tooltip_type)
   validator.expect_argument_types({validator.optional('string')}, tooltip_type)
   
   local custom_tooltips = radiant.entities.get_entity_data(item_or_type, 'stonehearth_ace:custom_tooltip')
   if custom_tooltips and tooltip_type then
      custom_tooltips = custom_tooltips[tooltip_type]
   end

   response:resolve({custom_tooltips = custom_tooltips or {}})
end

return CustomTooltipsCallHandler