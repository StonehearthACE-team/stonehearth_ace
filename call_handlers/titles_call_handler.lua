local validator = radiant.validator

local TitlesCallHandler = class()

function TitlesCallHandler:select_title_command(session, response, entity, title, rank)
   validator.expect_argument_types({'Entity', validator.optional('string'), validator.optional('number')}, entity, title, rank)

   local unit_info = entity:get_component('stonehearth:unit_info')
   if unit_info then
      unit_info:select_title(title, rank)
   end
end

return TitlesCallHandler